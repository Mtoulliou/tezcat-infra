output "group_url" {
  description = "URL du groupe tezcat"
  value       = gitlab_group.tezcat.web_url
}

output "repos_git" {
  description = "URLs de clone HTTPS des projets"
  value       = { for k, v in gitlab_project.tezcat : k => v.http_url_to_repo }
}

output "repos_ssh" {
  description = "URLs de clone SSH des projets (port 2222)"
  value       = { for k, v in gitlab_project.tezcat : k => v.ssh_url_to_repo }
}
