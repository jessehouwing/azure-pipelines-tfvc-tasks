# Release Notes
> **1-12-2016**

> - Add: throw error on server workspaces. They are not supported. Please upgrade to Agent 2.0 or configure your Project Collection to default to local workspaces.

> **18-10-2016**

> - FIX: working directory on 2.* agent

> **3-6-2016**

> - Updated all multiline textboxes to have more lines by default and to be resizable on browsers that support it.
> - Added "Skip on Shelveset Build" to the Check-in task.

> **4-4-2016**

> - Added "Updated Gated Changes" task which will allow you to check in generated and updated files as part of a gated checkin build.
> - Added "Skip on Gated Build" to the Checkin task to prevent issues on gated builds.

# Description
A set of Build tasks for TFS 2015 and Visual Studio Team Services that enables you to interact with the TFVC repository. Supported operations are:

* [Add](https://github.com/jessehouwing/vsts-tfvc-tasks/wiki/Add)
* [Check in changes](https://github.com/jessehouwing/vsts-tfvc-tasks/wiki/Check-in) 
* [Delete](https://github.com/jessehouwing/vsts-tfvc-tasks/wiki/Delete)
* [Undo changes](https://github.com/jessehouwing/vsts-tfvc-tasks/wiki/Undo) 
* [Update gated changes](https://github.com/jessehouwing/vsts-tfvc-tasks/wiki/Shelve) 

# Documentation

Please check the [Wiki](https://github.com/jessehouwing/vsts-tfvc-tasks/wiki).

# Planned features

Possible additional features:

 * Download files from Source Control (TFVC) in Build and Release.
 * Unshelve shelveset

If you have ideas or improvements to existing tasks, don't hesitate to leave feedback or [file an issue](https://github.com/jessehouwing/vsts-tfvc-tasks/issues).
