const addrs = {
  mainnet: {
    USDC: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
    WETH: '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2',
    CRV: '0xD533a949740bb3306d119CC777fa900bA034cd52',
    CVX: '0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B',
    SNX: '0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F',
    UniswapV3Router: '0xE592427A0AEce92De3Edee1F18E0157C05861564',
  },
};

export const levConvex = [
  {
    name: 'USDC-levConvex-sUSD',
    type: 'levConvex',
    curveAdapter: '0xbfB212e5D9F880bf93c47F3C32f6203fa4845222',
    convexRewardPool: '0xbEf6108D1F6B85c4c9AA3975e15904Bb3DFcA980',
    creditFacade: '0x61fbb350e39cc7bF22C01A469cf03085774184aa',
    convexBooster: '0xB548DaCb7e5d61BF47A026903904680564855B4E',
    coinId: 1, // curve token index
    underlying: addrs.mainnet.USDC,
    leverageFactor: 500,
    farmRouter: addrs.mainnet.UniswapV3Router,
    farmTokens: [addrs.mainnet.CRV, addrs.mainnet.CVX, addrs.mainnet.SNX],
    harvestPath: [addrs.mainnet.WETH, addrs.mainnet.USDC],
    chain: 'mainnet',
  },
];
