
$local_branch = git rev-parse --abbrev-ref HEAD

$valid_branch_regex = "^((feature|bug)\/(\d|[1-9]\d*)\.(\d|[1-9]\d*)\.(\d|[1-9]\d*)\/[a-z0-9.-]+)|((release|integration)\/(\d|[1-9]\d*)\.(\d|[1-9]\d*)\.(\d|[1-9]\d*)+)$"
$message = "There is something wrong with your branch name. Branch names in this project must adhere to this contract: $valid_branch_regex. Your commit will be rejected. You should rename your branch to a valid name and try again."
if (! $local_branch -match $valid_branch_regex) {
	Write-Host $message
	Exit 1
}

$files = git ls-files --cached | grep -x '.*sc-internal.*'
if ($files.Length -gt 0)
{
	Write-Host "Attempting to commit sc-internal files. Your commit is rejected."
	exit 1
}

