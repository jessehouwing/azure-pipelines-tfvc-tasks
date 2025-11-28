@{
    RootModule = 'VstsTaskSdk.psm1'
    ModuleVersion = '0.21.2' # Do not modify. This value gets replaced at build time with the value from the package.json.
    GUID = 'bbed04e2-4e8e-4089-90a2-58b858fed8d8'
    Author = 'Microsoft Corporation'
    CompanyName = 'Microsoft Corporation'
    Copyright = '(c) Microsoft Corporation. All rights reserved.'
    Description = 'VSTS Task SDK'
    PowerShellVersion = '3.0'
    FunctionsToExport = '*'
    CmdletsToExport = ''
    VariablesToExport = '*'
    AliasesToExport = ''
    PrivateData = @{
        PSData = @{
            ProjectUri = 'https://github.com/Microsoft/azure-pipelines-task-lib'
            CommitHash = 'a8cfa114409638f68d611154add61dc0d46f65d4' # Do not modify. This value gets replaced at build time.
        }
    }
    HelpInfoURI = 'https://github.com/Microsoft/azure-pipelines-task-lib'
    DefaultCommandPrefix = 'Vsts'
}
