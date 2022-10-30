## Invariants

This file lists various properties that should always true within the Isomorph system.

- Collateral virtual prices are monotonically increasing, they should only ever get bigger when updated.

- Vaults should only be able to interact with the collateral relating to their AssetType.

- Only Vaults and the external `CollateralBook.updateVirtualPriceSlowly()` should be able to change virtualPrices and update times of collaterals.

- Only the original loan holder should be able to increase their own loan.

- Repaid loans should either be burned if they relate to the loan principle or sent to the treasury if they relate to accrued interest.

- If the daily total loans of a Vault is reached it should not be possible to mint any more moUSD from that Vault until a day has passed since the daily total having been reached for that Vault.

- To fully clear a loan, the loan being repaid should always exceed the original borrowed sum.

- It should be impossible to open and close a loan for less than $0.001 paid in transaction fees on Optimism mainnet.

- If a user's loan is under the liquidation margin then any user should be able to liquidate them profitable so long as the liquidation amount is greater than $3 (amounts under this may not be profitable due to transaction fees incurred).

 - calling a liquidation on a user whos loan is above the liquidation margin point should always revert.
