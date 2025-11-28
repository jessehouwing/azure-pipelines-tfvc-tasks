# Release Notes
> - **28-11-2025** - Added preview support for runners with Visual Studio 2026, required v3 of the extension and tasks.
> - **28-11-2025** - Fixed [#118 Error: Cannot convert the "Microsoft.TeamFoundation.Client.TfsClientCredentials" value of type "System.String" to type "System.Type".](https://github.com/jessehouwing/azure-pipelines-tfvc-tasks/issues/118)
> - **26-05-2020** - Fixed [#99 Error: Get-VstsTfsClientCredentials : ScriptHalted](https://github.com/jessehouwing/azure-pipelines-tfvc-tasks/issues/99)
> - **21-04-2020** - Added do not sync sources step. Prevents Azure Pipelines from automatically checking out the sources.
> - **02-01-2020** - Fixed [#95 Checkin V2 task doesn't support custom author (but task.json has them)](https://github.com/jessehouwing/azure-pipelines-tfvc-tasks/issues/95). 
> - **23-12-2019** - Fixed [#91 Azure DevOps Agent running on https failed with TLS 1.2](https://github.com/jessehouwing/azure-pipelines-tfvc-tasks/issues/91).
> - **23-10-2019** - [Fixed "Could not load Newtonsoft.JSon" when Visual Studio 2019 is installed on the agent](https://github.com/microsoft/azure-pipelines-task-lib/issues/580).

# Description
A set of Build tasks for Team Foundation Server, Azure DevOps Server and Azure Pipelines that enables you to interact with the TFVC repository. Supported operations are:

* [Add](https://github.com/jessehouwing/azure-pipelines-tfvc-tasks/wiki/Add)
* [Check in changes](https://github.com/jessehouwing/azure-pipelines-tfvc-tasks/wiki/Check-in) 
* [Delete](https://github.com/jessehouwing/azure-pipelines-tfvc-tasks/wiki/Delete)
* [Undo changes](https://github.com/jessehouwing/azure-pipelines-tfvc-tasks/wiki/Undo) 
* [Update gated changes](https://github.com/jessehouwing/azure-pipelines-tfvc-tasks/wiki/Shelve) 
* Do not Sync Sources

# Documentation

Please check the [Wiki](https://github.com/jessehouwing/azure-pipelines-tfvc-tasks/wiki).

