## Invariants

This file lists various properties that should always true within the Isomorph system.

- Collateral virtual prices are monotonically increasing, they should only ever get bigger.

- Vaults should only be able to interact with the collateral relating to their AssetType.

- Only Vaults and the external `CollateralBook.updateVirtualPriceSlowly()` should be able to change virtualPrices and update times of collaterals.

- Only the original loan holder should be able to increase their own loan.
