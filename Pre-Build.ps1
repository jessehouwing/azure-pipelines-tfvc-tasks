Copy-Item tf-vc-shared\v1\* tf-vc-delete\v1 -force -recurse -exclude *.*proj
Copy-Item tf-vc-shared\v1\* tf-vc-add\v1 -force -recurse -exclude *.*proj
Copy-Item tf-vc-shared\v1\* tf-vc-undo\v1 -force -recurse -exclude *.*proj
Copy-Item tf-vc-shared\v1\* tf-vc-checkin\v1 -force -recurse -exclude *.*proj
Copy-Item tf-vc-shared\v1\* tf-vc-checkout\v1 -force -recurse -exclude *.*proj
Copy-Item tf-vc-shared\v1\* tf-vc-shelveset-update\v1 -force -recurse -exclude *.*proj

Copy-Item tf-vc-shared\v2\* tf-vc-delete\v2 -force -recurse -exclude *.*proj
Copy-Item tf-vc-shared\v2\* tf-vc-add\v2 -force -recurse -exclude *.*proj
Copy-Item tf-vc-shared\v2\* tf-vc-undo\v2 -force -recurse -exclude *.*proj
Copy-Item tf-vc-shared\v2\* tf-vc-checkin\v2 -force -recurse -exclude *.*proj
Copy-Item tf-vc-shared\v2\* tf-vc-checkout\v2 -force -recurse -exclude *.*proj
Copy-Item tf-vc-shared\v2\* tf-vc-shelveset-update\v2 -force -recurse -exclude *.*proj