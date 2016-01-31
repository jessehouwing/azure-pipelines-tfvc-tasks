# vsts-tfvc-tasks

Is a set of Build tasks for TFS 2015 and Visual Studio Team Services that enables you to interact with the TFVC repository. Supported operations are:

* Add files
* Check in changes (detects delete and edit automatically)

# General warning

Checking in files during your build process is not something you should take lightly. There are multiple problems you may not be aware of when doing this:

 * When checking in sources during the build the CS number of the build doesn't match the code checked in.
 * When using Source and Symbol indexing the information to the original CS number is stored, not the actual code used to create the binaries. This may cause problems when using:
   * remote debugging, 
   * intellitrace, 
   * and test impact analysis.
 * Due to the fact that files always change, incremental builds won't work, and build performance will be slower.

I recommend setting up two builds:
 1. One to apply the changes based on some trigger
 2. One to build the code and is triggered by the changes from build 1.
