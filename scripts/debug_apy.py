import os
import logging
from yearn.v2.vaults import Vault
from yearn.apy.common import get_samples
from yearn.debug import Debug

logger = logging.getLogger(__name__)

def main():
  address = os.getenv("DEBUG_ADDRESS", None)
  if address:
    vault = Vault.from_address(address)
    vault.apy(get_samples())
    collected_variables = Debug().get_collected_variables()
    logger.info("*** Available variables for debugging ***")
    available_variables = [ k for k in locals().keys() if '__' not in k and 'pdb' not in k and 'self' != k and 'sys' != k ]
    logger.info(available_variables)
  else:
    print("no address specified via $DEBUG_ADDRESS")
