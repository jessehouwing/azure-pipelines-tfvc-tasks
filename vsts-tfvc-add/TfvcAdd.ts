import * as tl from "vsts-task-lib/task";
import * as tr from "vsts-task-lib/toolrunner";

const pathToTf = tl.which("tf", true);

const itemSpec = tl.getPathInput("ItemSpec", true);
const recursion = tl.getInput("Recursion") !== "none";
const applyLocalItemExclusions = tl.getBoolInput("ApplyLocalitemExclusions");

const tfRunner = new tr.ToolRunner(pathToTf);
tfRunner.arg("vc");
tfRunner.arg("add");
tfRunner.arg(itemSpec);
tfRunner.arg("/noprompt");
tfRunner.argIf(recursion, "/recursive");
tfRunner.argIf(applyLocalItemExclusions, "/noignore")

let encoding, lock, additionalArguments;
tfRunner.argIf(encoding, `/encoding:${encoding}`);
tfRunner.argIf(lock, `/lock:${lock}`);
tfRunner.line(additionalArguments);

const endpoint = tl.getEndpointAuthorization("SystemVssConnection", false);

if (endpoint.scheme === "OAuth") {
    tfRunner.arg("/loginType:oauth");
    tfRunner.arg(`/login:.,${endpoint.parameters["AccessToken"]}`);
}

tfRunner.exec().fail(reason => { tl.setResult(tl.TaskResult.Failed, reason); });