// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { IntegrationTest } from "../common/IntegrationTest.sol";
import { FlashSwapTest } from "../common/FlashSwapTest.sol";
import { HLPSetup } from "./HLPSetup.sol";

contract HLPIntegration is IntegrationTest, HLPSetup, FlashSwapTest {}
