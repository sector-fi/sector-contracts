import { main as synapse } from './synapse';
import { main as stargate } from './stargate';
import { main as imxLend } from './imxLend';

synapse()
  .then(stargate)
  .then(imxLend)
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
