#!/bin/bash
#
# https://github.com/gitlabhq/gitlabhq/blob/stable/doc/install/installation.md
#
set -exu

test -e getup.nginx.site

START_DIR="$(dirname $(readlink -f $0))"
START=`date +%s`
SERVER_FQDN=getupcloud.com
GITLAB_ADMIN_PASSWORD=${GITLAB_ADMIN_PASSWORD:-"`openssl rand -base64 16`"}
GITLAB_MYSQL_PASSWORD=${GITLAB_MYSQL_PASSWORD:-"`openssl rand -base64 16`"}
GITLAB_MYSQL_PASSWORD_DEVEL=${GITLAB_MYSQL_PASSWORD_DEVEL:-"`openssl rand -base64 16`"}
GITLAB_DATABASE=gitlab
LOG=$START_DIR/install-gitlab-$START.log

if tty -s; then
	read -p 'Continue installation ? [y/N] ' x
	if [ $? -ne 0 -o "$x" != 'y' ]; then
		[ "$x" == 'Y' ] || exit 1
	fi
fi

echo "All output redirected to $LOG"
exec &>$LOG

cat <<EOF
 - Gitlab (site)
   - Gitlab admin username: "admin@$SERVER_FQDN"
   - Gitlab admin password: "$GITLAB_ADMIN_PASSWORD"

 - MySQL
   - Gitlab mysql username: "gitlab@localhost"
   - Gitlab mysql pass:     "$GITLAB_MYSQL_PASSWORD"

Start time: $START

#################################################################

EOF

# dependencies
##############

apt-get update
apt-get upgrade -y
apt-get install -y wget curl gcc checkinstall libxml2-dev libxslt-dev \
  libcurl4-openssl-dev libreadline6-dev libc6-dev libssl-dev libmysql++-dev \
  make build-essential zlib1g-dev libicu-dev redis-server openssh-server \
  git-core python-dev python-pip libyaml-dev postfix libpq-dev
pip install pygments

# ruby
######

curl http://ftp.ruby-lang.org/pub/ruby/1.9/ruby-1.9.3-p194.tar.gz | tar xvz
cd ruby-1.9.3-p194
./configure
make && make install

# users
#######

adduser \
  --system \
  --shell /bin/sh \
  --gecos 'git version control' \
  --group \
  --disabled-password \
  --home /home/git \
  git

adduser --disabled-login --gecos 'gitlab system' gitlab
usermod -a -G git gitlab
usermod -a -G gitlab git
sudo -H -u gitlab ssh-keygen -q -N '' -t dsa -f /home/gitlab/.ssh/id_dsa

# gitolite
##########

cd /home/git
sudo -H -u git git clone -b gl-v304 https://github.com/gitlabhq/gitolite.git /home/git/gitolite
sudo -H -u git mkdir bin
sudo -H -u git sh -c 'echo -e "PATH=\$PATH:/home/git/bin\nexport PATH" >> /home/git/.profile'
sudo -H -u git sh -c 'gitolite/install -ln /home/git/bin'
cp /home/gitlab/.ssh/id_dsa.pub /home/git/gitlab.pub
chmod 0444 /home/git/gitlab.pub
sudo -H -u git sh -c "PATH=/home/git/bin:$PATH; gitolite setup -pk /home/git/gitlab.pub"
chmod -R g+rwX /home/git/repositories/
chown -R git:git /home/git/repositories/
# clone admin repo to add localhost to known_hosts
# & be sure your user has access to gitolite
cat >> ~gitlab/.ssh/config <<-EOF
	Host localhost
	  StrictHostKeyChecking no
	  ForwardX11 no
EOF
chown gitlab:gitlab ~gitlab/.ssh/config
sudo -H -u gitlab git clone git@localhost:gitolite-admin.git /tmp/gitolite-admin
# if succeed  you can remove it
rm -rf /tmp/gitolite-admin

# mysql
#######

apt-get install -y mysql-server mysql-client libmysqlclient-dev
service mysql restart
sleep 2
mysql -u root <<-EOF
  CREATE DATABASE IF NOT EXISTS $GITLAB_DATABASE DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;
  CREATE USER gitlab@localhost IDENTIFIED BY '$GITLAB_MYSQL_PASSWORD';
  GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER ON $GITLAB_DATABASE.* TO gitlab@localhost;
EOF

# gitlab
########

cd /home/gitlab
# stable (with getup configs)
sudo -H -u gitlab git clone -b stable-getup https://github.com/caruccio/gitlabhq.git gitlab
# stable (official)
#sudo -H -u gitlab git clone -b stable https://github.com/gitlabhq/gitlabhq.git gitlab
# devel (official)
#sudo -H -u gitlab git clone -b master https://github.com/gitlabhq/gitlabhq.git gitlab
cd gitlab

function eval_file()
{
  sed "$1" \
    -e "s/@@SERVER_FQDN@@/$SERVER_FQDN/g"
}

eval_file config/gitlab.yml.getup > config/gitlab.yml
eval_file config/database.yml.getup > config/database.yml
eval_file db/fixtures/production/001_admin.rb.getup > db/fixtures/production/001_admin.rb
cp config/unicorn.rb.getup config/unicorn.rb

gem install charlock_holmes --version '0.6.9'
gem install bundler
gem install rb-inotify
sudo -u gitlab git config --global user.email "admin@$SERVER_FQDN"
sudo -u gitlab git config --global user.name "GitLab"
sudo -u gitlab bundle install --without development test sqlite postgres --deployment
sudo -u gitlab bundle exec rake gitlab:app:setup RAILS_ENV=production
cp ./lib/hooks/post-receive /home/git/.gitolite/hooks/common/post-receive
chown git:git /home/git/.gitolite/hooks/common/post-receive
sudo -u gitlab RAILS_ENV=production bundle exec rake assets:precompile
chown gitlab:gitlab . -R

wget https://raw.github.com/gitlabhq/gitlab-recipes/master/init.d/gitlab -P /etc/init.d/
chmod +x /etc/init.d/gitlab
echo 'NOTE: following command last aprox. 15 min'
update-rc.d gitlab defaults 21
service gitlab start

# nginx
#######

apt-get install -y nginx
# https://raw.github.com/gitlabhq/gitlab-recipes/master/nginx/gitlab
for file in $START_DIR/*.nginx.site; do
	file=${file##*/}
	server=${file%.nginx.site}
	eval_file $file > /etc/nginx/sites-available/$server
	ln -fs /etc/nginx/sites-available/$server /etc/nginx/sites-enabled/$server
done

#service mysql restart
#service gitlab stop
#service gitlab start
#service nginx restart

echo "End time: `date +%s`" >> ~/install-gitlab-$START.log
