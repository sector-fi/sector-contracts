import { strategies } from './config';
import { addStratToConfig } from '../../utils';

export const main = async () => {
  for (const strategy of strategies) await addStrategy(strategy);
};

const addStrategy = async (strategy) => {
  const config = {
    a_underlying: strategy.underlying,
    b_strategy: strategy.strategy,
    x_chain: 'ARBITRUM',
  };
  await addStratToConfig(strategy.name, config, strategy);
};
