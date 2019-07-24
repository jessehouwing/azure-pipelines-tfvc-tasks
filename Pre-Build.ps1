Copy-Item tfvc-shared\* tfvc-delete -force -recurse -exclude *.*proj
Copy-Item tfvc-shared\* tfvc-add -force -recurse -exclude *.*proj
Copy-Item tfvc-shared\* tfvc-undo -force -recurse -exclude *.*proj
Copy-Item tfvc-shared\* tfvc-checkin -force -recurse -exclude *.*proj
Copy-Item tfvc-shared\* tfvc-checkout -force -recurse -exclude *.*proj
Copy-Item tfvc-shared\* tfvc-updateshelveset -force -recurse -exclude *.*proj