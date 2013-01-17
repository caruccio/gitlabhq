class KeyObserver < ActiveRecord::Observer
  include GitHost

  def after_save(key)
    git_host.set_key(key.identifier, key.key, key.projects)
    SystemHook.all_hooks_fire({
      event_name: "key_save",
      title: key.title,
      key: key.key,
      owner_email: key.user.email,
      owner_name: key.user.name,
      projects: key.projects,
      created_at: key.created_at,
    })
  end

  def after_destroy(key)
    return if key.is_deploy_key && !key.last_deploy?
    git_host.remove_key(key.identifier, key.projects)
    SystemHook.all_hooks_fire({
      event_name: "key_destroy",
      title: key.title,
      key: key.key,
      owner_email: key.user.email,
      owner_name: key.user.name,
      projects: key.projects,
      created_at: key.created_at,
    })
  end
end
