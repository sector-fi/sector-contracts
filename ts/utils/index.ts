export * from './network';
export * from './timelock';

export const waitFor = (delay: number): Promise<void> =>
  new Promise((resolve) => setTimeout(resolve, delay));
