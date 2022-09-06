// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { FixedPointMathLib } from "../../libraries/FixedPointMathLib.sol";

import "../utils/UQ112x112.sol";

import { MockERC20 as ERC20 } from "./MockERC20.sol";

import "hardhat/console.sol";

contract MockPair is ERC20 {
	using SafeMath for uint256;
	using UQ112x112 for uint224;

	uint256 public constant MINIMUM_LIQUIDITY = 10**3;
	bytes4 private constant SELECTOR = bytes4(keccak256(bytes("transfer(address,uint256)")));

	address public factory;
	address public token0;
	address public token1;

	uint112 private reserve0; // uses single storage slot, accessible via getReserves
	uint112 private reserve1; // uses single storage slot, accessible via getReserves

	uint256 public kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event

	function getReserves()
		public
		view
		returns (
			uint112 _reserve0,
			uint112 _reserve1,
			uint32 _blockTimestampLast
		)
	{
		_reserve0 = reserve0;
		_reserve1 = reserve1;
		_blockTimestampLast = 0;
	}

	event Mint(address indexed sender, uint256 amount0, uint256 amount1);
	event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
	event Swap(
		address indexed sender,
		uint256 amount0In,
		uint256 amount1In,
		uint256 amount0Out,
		uint256 amount1Out,
		address indexed to
	);
	event Sync(uint112 reserve0, uint112 reserve1);

	constructor(
		string memory _name,
		string memory _symbol,
		uint8 decimals_
	) ERC20(_name, _symbol, decimals_) {
		_decimals = _decimals;
		factory = msg.sender;
	}

	// called once at time of deployment
	function initialize(address _token0, address _token1) external {
		require(msg.sender == factory, "UniswapV2: FORBIDDEN"); // sufficient check
		token0 = _token0;
		token1 = _token1;
	}

	// update reserves
	function _update(uint256 balance0, uint256 balance1) private {
		require(
			balance0 <= type(uint112).max && balance1 <= type(uint112).max,
			"MockPair: OVERFLOW"
		);
		reserve0 = uint112(balance0);
		reserve1 = uint112(balance1);
		emit Sync(reserve0, reserve1);
	}

	function mint(address to) external returns (uint256 liquidity) {
		(uint112 _reserve0, uint112 _reserve1, ) = getReserves(); // gas savings;
		uint256 balance0 = IERC20(token0).balanceOf(address(this));
		uint256 balance1 = IERC20(token1).balanceOf(address(this));
		uint256 amount0 = balance0.sub(_reserve0);
		uint256 amount1 = balance1.sub(_reserve1);
		uint256 _totalSupply = totalSupply(); // not necessary without _mintFee but leaving in here
		if (_totalSupply == 0) {
			liquidity = FixedPointMathLib.sqrt(amount0.mul(amount1)).sub(MINIMUM_LIQUIDITY);
			_mint(address(0xbeef), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
		} else {
			liquidity = Math.min(
				amount0.mul(_totalSupply) / _reserve0,
				amount1.mul(_totalSupply) / _reserve1
			);
		}
		require(liquidity > 0, "MockPair: INSUFFICIENT_LIQUIDITY_MINTED");
		_mint(to, liquidity);
		_update(balance0, balance1);
		kLast = uint256(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
		emit Mint(msg.sender, amount0, amount1);
	}

	function burn(address to) external returns (uint256 amount0, uint256 amount1) {
		address _token0 = token0; // gas savings
		address _token1 = token1; // gas savings
		uint256 balance0 = IERC20(_token0).balanceOf(address(this));
		uint256 balance1 = IERC20(_token1).balanceOf(address(this));
		uint256 liquidity = balanceOf(address(this));

		uint256 _totalSupply = totalSupply(); // not necessary without _mintFee but leaving in here
		amount0 = liquidity.mul(balance0) / _totalSupply; // using balances ensures pro-rata distribution
		amount1 = liquidity.mul(balance1) / _totalSupply; // using balances ensures pro-rata distribution
		require(amount0 > 0 && amount1 > 0, "MockPair: INSUFFICIENT_LIQUIDITY_BURNED");
		_burn(address(this), liquidity);
		IERC20(_token0).transfer(to, amount0);
		IERC20(_token1).transfer(to, amount1);
		balance0 = IERC20(_token0).balanceOf(address(this));
		balance1 = IERC20(_token1).balanceOf(address(this));

		_update(balance0, balance1);
		kLast = uint256(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
		emit Burn(msg.sender, amount0, amount1, to);
	}

	// this low-level function should be called from a contract which performs important safety checks
	function swap(
		uint256 amount0Out,
		uint256 amount1Out,
		address to,
		bytes calldata data
	) external {
		require(amount0Out > 0 || amount1Out > 0, "MockPair: INSUFFICIENT_OUTPUT_AMOUNT");
		(uint112 _reserve0, uint112 _reserve1, ) = getReserves(); // gas savings
		require(
			amount0Out < _reserve0 && amount1Out < _reserve1,
			"MockPair: INSUFFICIENT_LIQUIDITY"
		);

		uint256 balance0;
		uint256 balance1;
		{
			// scope for _token{0,1}, avoids stack too deep errors
			address _token0 = token0;
			address _token1 = token1;
			require(to != _token0 && to != _token1, "MockPair: INVALID_TO");
			if (amount0Out > 0) IERC20(_token0).transfer(to, amount0Out); // optimistically transfer tokens
			if (amount1Out > 0) IERC20(_token1).transfer(to, amount1Out); // optimistically transfer tokens
			balance0 = IERC20(_token0).balanceOf(address(this));
			balance1 = IERC20(_token1).balanceOf(address(this));
		}
		uint256 amount0In = balance0 > _reserve0 - amount0Out
			? balance0 - (_reserve0 - amount0Out)
			: 0;
		uint256 amount1In = balance1 > _reserve1 - amount1Out
			? balance1 - (_reserve1 - amount1Out)
			: 0;
		require(amount0In > 0 || amount1In > 0, "MockPair: INSUFFICIENT_INPUT_AMOUNT");
		{
			// scope for reserve{0,1}Adjusted, avoids stack too deep errors
			uint256 balance0Adjusted = balance0.mul(1000).sub(amount0In.mul(3));
			uint256 balance1Adjusted = balance1.mul(1000).sub(amount1In.mul(3));
			require(
				balance0Adjusted.mul(balance1Adjusted) >=
					uint256(_reserve0).mul(_reserve1).mul(1000**2),
				"MockPair: K"
			);
		}
		_update(balance0, balance1);
		emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
	}

	// force balances to match reserves
	function skim(address to) external {
		address _token0 = token0; // gas savings
		address _token1 = token1; // gas savings
		IERC20(_token0).transfer(to, IERC20(_token0).balanceOf(address(this)).sub(reserve0));
		IERC20(_token1).transfer(to, IERC20(_token1).balanceOf(address(this)).sub(reserve1));
	}

	// force reserves to match balances
	function sync() external {
		_update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)));
	}
}
