Copy-Item vsts-tfvc-shared\* vsts-tfvc-delete -force -recurse -exclude *.*proj
Copy-Item vsts-tfvc-shared\* vsts-tfvc-add -force -recurse -exclude *.*proj
Copy-Item vsts-tfvc-shared\* vsts-tfvc-undo -force -recurse -exclude *.*proj
Copy-Item vsts-tfvc-shared\* vsts-tfvc-checkin -force -recurse -exclude *.*proj
Copy-Item vsts-tfvc-shared\* vsts-tfvc-checkout -force -recurse -exclude *.*proj
Copy-Item vsts-tfvc-shared\* vsts-tfvc-updateshelveset -force -recurse -exclude *.*proj