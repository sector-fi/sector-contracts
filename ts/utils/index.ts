export * from './network';
export * from './timelock';
export * from './token';
export * from './socketAPI';
// export * from './xChainUtils';

export const waitFor = (delay: number): Promise<void> =>
  new Promise((resolve) => setTimeout(resolve, delay));
