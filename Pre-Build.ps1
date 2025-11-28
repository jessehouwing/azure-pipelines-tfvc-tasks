Copy-Item $PSScriptRoot\tf-vc-shared\v1\* $PSScriptRoot\tf-vc-delete\v1 -force -recurse -exclude *.*proj
Copy-Item $PSScriptRoot\tf-vc-shared\v1\* $PSScriptRoot\tf-vc-add\v1 -force -recurse -exclude *.*proj
Copy-Item $PSScriptRoot\tf-vc-shared\v1\* $PSScriptRoot\tf-vc-undo\v1 -force -recurse -exclude *.*proj
Copy-Item $PSScriptRoot\tf-vc-shared\v1\* $PSScriptRoot\tf-vc-checkin\v1 -force -recurse -exclude *.*proj
Copy-Item $PSScriptRoot\tf-vc-shared\v1\* $PSScriptRoot\tf-vc-checkout\v1 -force -recurse -exclude *.*proj
Copy-Item $PSScriptRoot\tf-vc-shared\v1\* $PSScriptRoot\tf-vc-shelveset-update\v1 -force -recurse -exclude *.*proj

Copy-Item $PSScriptRoot\tf-vc-shared\v2\* $PSScriptRoot\tf-vc-delete\v2 -force -recurse -exclude *.*proj
Copy-Item $PSScriptRoot\tf-vc-shared\v2\* $PSScriptRoot\tf-vc-add\v2 -force -recurse -exclude *.*proj
Copy-Item $PSScriptRoot\tf-vc-shared\v2\* $PSScriptRoot\tf-vc-undo\v2 -force -recurse -exclude *.*proj
Copy-Item $PSScriptRoot\tf-vc-shared\v2\* $PSScriptRoot\tf-vc-checkin\v2 -force -recurse -exclude *.*proj
Copy-Item $PSScriptRoot\tf-vc-shared\v2\* $PSScriptRoot\tf-vc-checkout\v2 -force -recurse -exclude *.*proj
Copy-Item $PSScriptRoot\tf-vc-shared\v2\* $PSScriptRoot\tf-vc-shelveset-update\v2 -force -recurse -exclude *.*proj
Copy-Item $PSScriptRoot\tf-vc-shared\v2\ps_modules\VstsTaskSdk\* $PSScriptRoot\tf-vc-dontsync\v2\ps_modules\VstsTaskSdk\ -force -recurse -exclude *.*proj

Copy-Item $PSScriptRoot\tf-vc-shared\v3\* $PSScriptRoot\tf-vc-delete\v3 -force -recurse -exclude *.*proj
Copy-Item $PSScriptRoot\tf-vc-shared\v3\* $PSScriptRoot\tf-vc-add\v3 -force -recurse -exclude *.*proj
Copy-Item $PSScriptRoot\tf-vc-shared\v3\* $PSScriptRoot\tf-vc-undo\v3 -force -recurse -exclude *.*proj
Copy-Item $PSScriptRoot\tf-vc-shared\v3\* $PSScriptRoot\tf-vc-checkin\v3 -force -recurse -exclude *.*proj
Copy-Item $PSScriptRoot\tf-vc-shared\v3\* $PSScriptRoot\tf-vc-checkout\v3 -force -recurse -exclude *.*proj
Copy-Item $PSScriptRoot\tf-vc-shared\v3\* $PSScriptRoot\tf-vc-shelveset-update\v3 -force -recurse -exclude *.*proj
Copy-Item $PSScriptRoot\tf-vc-shared\v3\ps_modules\VstsTaskSdk\* $PSScriptRoot\tf-vc-dontsync\v3\ps_modules\VstsTaskSdk\ -force -recurse -exclude *.*proj