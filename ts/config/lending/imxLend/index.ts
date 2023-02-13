import { strategies } from './config';
import { addStratToConfig, chainToEnv } from '../../utils';

export const main = async () => {
  for (const strategy of strategies) await addStrategy(strategy);
};

const addStrategy = async (strategy) => {
  const config = {
    a_underlying: strategy.underlying,
    b_strategy: strategy.strategy,
    c_acceptsNativeToken: !!strategy.acceptsNativeToken,
    x_chain: chainToEnv[strategy.chain],
  };
  await addStratToConfig(strategy.name, config, strategy);
};
