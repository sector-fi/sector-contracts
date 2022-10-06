export * from './network';
export * from './timelock';
export * from './token';
export * from './socketAPI';

export const waitFor = (delay: number): Promise<void> =>
  new Promise((resolve) => setTimeout(resolve, delay));
