import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { setMiningInterval } from "../utils";

const func: DeployFunction = async function ({
  network,
}: HardhatRuntimeEnvironment) {
  if (network.name == "localhost") {
    console.log("setting mining int");
    await setMiningInterval(5000);
  }
};

export default func;
func.tags = ["fork"];
func.runAtTheEnd = true;
