// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SectorTest } from "../../utils/SectorTest.sol";
import { IAddressProvider } from "interfaces/gearbox/IAddressProvider.sol";
import { IAccountFactoryGetters } from "interfaces/gearbox/IAccountFactoryGetters.sol";
import { ICreditFacade, ICreditManagerV2, MultiCall, ICreditFacadeExceptions } from "interfaces/gearbox/ICreditFacade.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IACL } from "interfaces/gearbox/IACL.sol";
import { IDegenNFT } from "interfaces/gearbox/IDegenNFT.sol";
import { IPriceOracleV2 } from "interfaces/gearbox/IPriceOracleV2.sol";
import { ICurvePool } from "interfaces/curve/ICurvePool.sol";

import "hardhat/console.sol";

contract GearboxTest is SectorTest {
	string RPC_URL = vm.envString("ETH_RPC_URL");
	uint256 BLOCK = vm.envUint("ETH_BLOCK");

	IAddressProvider addressProvider = IAddressProvider(0xcF64698AFF7E5f27A11dff868AF228653ba53be0);
	IAccountFactoryGetters accFactory;

	address ETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
	address stETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
	address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

	address stETHAdapter = 0x0Ad2Fc10F677b2554553DaF80312A98ddb38f8Ef;

	IPriceOracleV2 public priceOracle;
	ICreditManagerV2 creditManager;

	// ETH
	ICreditFacade creditFacade = ICreditFacade(0xC59135f449bb623501145443c70A30eE648Fa304);

	// USDC
	// ICreditFacade creditFacade = ICreditFacade(0x61fbb350e39cc7bF22C01A469cf03085774184aa);

	// DAI
	// ICreditFacade creditFacade = ICreditFacade(0xf6f4F24ae50206A07B8B32629AeB6cb1837d854F);
	ERC20 underlying;
	uint256 decimals;
	uint256 ethDec;

	uint256 leverageFactor = 500;
	address credAcc;

	function setUp() public {
		uint256 fork = vm.createFork(RPC_URL, BLOCK);
		vm.selectFork(fork);

		accFactory = IAccountFactoryGetters(addressProvider.getAccountFactory());

		priceOracle = IPriceOracleV2(addressProvider.getPriceOracle());
		console.log("priceOracle", address(priceOracle));

		// address configurator = IACL(addressProvider.getACL()).owner();
		// vm.prank(configurator);

		IDegenNFT degenNFT = IDegenNFT(creditFacade.degenNFT());
		address minter = degenNFT.minter();

		vm.prank(minter);
		degenNFT.mint(address(this), 10);

		underlying = ERC20(USDC);
		decimals = underlying.decimals();
		ethDec = ERC20(ETH).decimals();

		uint256 amount = 50000 * 10**decimals;

		deal(address(underlying), self, amount);
		creditManager = creditFacade.creditManager();
		underlying.approve(address(creditManager), amount);

		uint256 borrowAmnt = underlyingToShort((amount * leverageFactor) / 100);

		MultiCall[] memory calls = new MultiCall[](1);
		calls[0] = MultiCall({
			target: address(creditFacade),
			callData: abi.encodeWithSelector(
				ICreditFacade.addCollateral.selector,
				self,
				address(underlying),
				amount
			)
		});

		creditFacade.openCreditAccountMulticall(borrowAmnt, self, calls, 0);

		credAcc = creditManager.getCreditAccountOrRevert(address(this));
	}

	function testGearbox() public {
		console.log("ubal", underlying.balanceOf(credAcc));
		(uint256 total, uint256 twv) = creditFacade.calcTotalValue(credAcc);
		(, , uint256 borrowAmountWithInterestAndFees) = creditManager
			.calcCreditAccountAccruedInterest(credAcc);
		console.log(
			"lt",
			creditManager.liquidationThresholds(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84)
		);
		console.log("health", creditFacade.calcCreditAccountHealthFactor(credAcc));
		console.log("total borrowed, twv", total, twv);
		console.log("borrowAmountWithInterestAndFees", borrowAmountWithInterestAndFees);
		assertEq(creditFacade.hasOpenedCreditAccount(self), true);
	}

	function testCurveMultiCall() public {
		uint256 balance = ERC20(ETH).balanceOf(credAcc);

		MultiCall[] memory calls = new MultiCall[](1);
		calls[0] = MultiCall({
			target: stETHAdapter,
			callData: abi.encodeWithSelector(ICurvePool.exchange.selector, 0, 1, balance, 0)
		});
		creditFacade.multicall(calls);
	}

	function testCloseAcc() public {
		vm.roll(1);
		MultiCall[] memory calls = new MultiCall[](0);
		deal(address(ETH), self, 1);
		ERC20(ETH).approve(address(creditManager), 1e18);
		creditFacade.closeCreditAccount(address(this), 0, false, calls);

		uint256 amount = 50000 * 10**decimals;
		uint256 borrowAmnt = underlyingToShort((amount * leverageFactor) / 100);

		deal(address(underlying), self, amount);
		creditManager = creditFacade.creditManager();
		underlying.approve(address(creditManager), amount);

		calls = new MultiCall[](1);
		calls[0] = MultiCall({
			target: address(creditFacade),
			callData: abi.encodeWithSelector(
				ICreditFacade.addCollateral.selector,
				self,
				address(underlying),
				amount
			)
		});
		creditFacade.openCreditAccountMulticall(borrowAmnt, self, calls, 0);

		credAcc = creditManager.getCreditAccountOrRevert(address(this));
		// assertEq(creditManager.getCreditAccountOrRevert(address(this)), credAcc);
	}

	function underlyingToShort(uint256 amount) public view returns (uint256) {
		return
			(amount * (10**ethDec) * priceOracle.getPrice(address(underlying))) /
			priceOracle.getPrice(ETH) /
			(10**decimals);
	}

	function shortToUnderlying(uint256 amount) public view returns (uint256) {
		return
			(amount * (10**ethDec) * priceOracle.getPrice(ETH)) /
			priceOracle.getPrice(address(underlying)) /
			(10**ethDec);
	}
}
