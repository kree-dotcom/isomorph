# CollateralBook.sol function purposes
The CollateralBook is responsible for recording the details of each collateral used by the system and is updated by Vaults to maintain the virtual prices and update times of each collateral. It also contains admin functions that allow the addition of new vaults, new collaterals and modifications of existing collaterals.
## Structures 

- Collateral
This stores the characteristics of each collateral added to the system. 


## Modifiers 
- collateralExists
 This modifier checks a collateral exists before interacting with it.

- onlyVault
This modifier is used to protect functions that should only be called by `Vaults`.

## Function 

- viewVirtualPriceforAsset
This is a function to assist testing and bots in viewing the `virtualPrice` of a collateral with needing to fetch the entire collateral struct, not strictly needed.

- viewLastUpdateTimeforAsset
This is a function to assist testing and bots in viewing the `lastUpdateTime` of a collateral with needing to fetch the entire collateral struct, not strictly needed.

- queueCollateralChange
This is the first call in a 2 stage process of changing an existing collateral's characteristics. This function cannot change a collaterals address, if this is needed then a new type of collateral must be added and 
the old collateral deactivated. This function is only callable by the Admin

- changeCollateralType
This is the second call in a 2 stage process of changing an existing collateral's characteristics. Note the queued data is not deleted once used however this is only callable by an Admin and only one change can be queued at a time meaning it would just repeat the same change if ran twice or more. This call can fail if the `virtualPrice` is very out-of-date as the old interest rate is used to update the `virtualPrice` first then the new values are set. 
//IMPORTANT THIS DOES NOT WIPE QUEUED VALUES ONCE SET, ADVISE TO DO SO.

- _changeCollateralParameters
An internal function used by `changeCollateralType` to update the collateral's characteristics.

- pauseCollateralType
This function enables an Admin to pause a collateral. In doing so the `collateralPaused` mapping of it's address is set to `True` and it's collateralValid mapping is set to `False`. We require the currencyKey to be provided alongside the collateralAddress as this is easier to spot errors in 
and so should prevent pausing of the wrong collateral

- unpauseCollateralType
This function enables an Admin to unpause a previously paused collateral. In doing so the `collateralPaused` mapping of it's address is set to `False` and it's collateralValid mapping is set to `True`. We require the currencyKey to be provided alongside the collateralAddress as this is easier to spot errors in and so should prevent pausing of the wrong collateral.
 
- setVaultAddress
//IMPORTANT THIS MUST BE EXPANDED TO ALLOW MULTIPLE VAULTS

- _updateVirtualPriceAndTime
This internal function is used whenever a `virtualPrice` and `lastUpdateTime` of a collateral is being updated. It contains sanity checks that the updated values are strictly larger than the existing values. The `virtualPrice` and `lastUpdateTime` should never decrease.
//ADD THIS AS AN INVARIANT

- vaultUpdateVirtualPriceAndTime
This external function allows the `Vaults` to update the `virtualPrice` and `lastUpdateTime` of a collateral. 

A wrapper around the internal `_updateVirtualPriceAndTime()` that allows the `Vault.sol` instance to update the virtualPrice by the same method as CollateralBook. 

- updateVirtualPriceSlowly

An external function callable by anyone. This enables any user to release a stuck collateral where it has been too long since an virtualPrice update and so trying to update in one block would exceed the block gas limit. It cannot be called with excessive updates that would bring the virtualPrice into the future time as this would lead to users being overcharged interest.

- addCollateralType

This function is used to add collateral to the system, it is only callable by the admin. Each collateral must be completely new to prevent overwriting of previous existing collateral as doing so would avoid the timelock on collateral changes. 
