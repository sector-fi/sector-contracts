// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { IntegrationTest } from "../common/IntegrationTest.sol";
import { FlashSwapTest } from "../common/FlashSwapTest.sol";
import { IMXSetup } from "./IMXSetup.sol";

contract IMXIntegration is IntegrationTest, IMXSetup, FlashSwapTest {}
