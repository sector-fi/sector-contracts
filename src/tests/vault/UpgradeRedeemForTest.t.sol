pragma solidity ^0.8.0;

import "forge-std/console.sol";
import "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SectorTest } from "./utils/SectorTest.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { AggregatorVaultU, RedeemParams, AuthConfig, FeeConfig } from "../vaults/sectorVaults/AggregatorVaultU.sol";

contract UpgradeTest is SectorTest {
    UpgradeableBeacon beacon;
    address implementation;

    function setUp() public {
        vm.createSelectFork("https://arb1.arbitrum.io/rpc");
        beacon = UpgradeableBeacon(0xE3aAD253773810C29F777d5A4b7AcB4065860366);
        implementation = address(new AggregatorVaultU());
    }

    function test_upgrade() public {
        vm.startPrank(beacon.owner());
        console.log("beacon implementation", beacon.implementation());
        beacon.upgradeTo(implementation);
        console.log("beacon implementation", beacon.implementation());
        vm.stopPrank();
    }

    function test_checkWithdrawPending() public {
        address user = 0x465AD9651f77f9BA68D7B0757200616CcD6306ad;
        address payable vaultAddress = payable(0x09e677692a17dA303A868D46C53aC53B1901D90E);
        AggregatorVaultU vault = AggregatorVaultU(vaultAddress);

        vm.startPrank(beacon.owner());
        console.log("beacon implementation", beacon.implementation());
        beacon.upgradeTo(implementation);
        console.log("beacon implementation", beacon.implementation());
        vm.stopPrank();

        address token = vault.underlying();
        console.log("token", token);
        uint256 prev_balUser = IERC20(token).balanceOf(user);
        uint256 prev_balVault = IERC20(token).balanceOf(vaultAddress);
        console.log("prev_balVault", prev_balVault);

        vault.redeemFor(user);

        uint256 post_balUser = IERC20(token).balanceOf(user);
        console.log("post_balUser", post_balUser);
        uint256 post_balVault = IERC20(token).balanceOf(vaultAddress);
        console.log("post_balVault", post_balVault);

        assertTrue(post_balUser > prev_balUser);
        assertTrue(post_balVault < prev_balVault);
    }
}