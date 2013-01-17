class KeyObserver < ActiveRecord::Observer
  include GitHost

  def after_save(key)
    r = git_host.set_key(key.identifier, key.key, key.projects)
    begin
      SystemHook.all_hooks_fire({
        event_name: "key_save",
        id: key.id,
        title: key.title,
        key: key.key,
        user_id: key.user.user_id,
        owner_email: key.user.email,
        owner_name: key.user.name,
        projects: key.projects,
        created_at: key.created_at,
      })
    rescue => ex
      puts "SystemHook error: failed POST: #{ex}"
    end
    r
  end

  def after_destroy(key)
    return if key.is_deploy_key && !key.last_deploy?
    r = git_host.remove_key(key.identifier, key.projects)
    begin
      SystemHook.all_hooks_fire({
        event_name: "key_destroy",
        id: key.id,
        title: key.title,
        key: key.key,
        user_id: key.user.user_id,
        owner_email: key.user.email,
        owner_name: key.user.name,
        projects: key.projects,
        created_at: key.created_at,
      })
    rescue => ex
      puts "SystemHook error: failed POST: #{ex}"
    end
    r
  end
end
