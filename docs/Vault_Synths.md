# Vault_Synths.sol function purposes

## Functions

### _checkIfCollateralIsActive
For the liquidation system assumptions to function correctly it is essential that when interacted with a synth is not frozen and its market is open. If frozen or untradable then liquidators cannot sell the collateral and so will not desire to execute liquidations.

- For Synths this function verifies that the synth being used for collateral is still tradable for sUSD using the Synthetix exchange contracts. This check entails four parts:
    1. If the Synthetix system as a whole is active.
    2. If exchanging between synths is active.
    3. If exchanging the specific synths involved in this trade is possible.
    4. If either of the specific synths involved is currently suspended.

    
### priceCollateralToUSD
This function allows us to price any collateral in USD.
In order to use the Synthetix pricing system for the value of a Synth collateral it is necessary for us to call the Synthetix exchange rate for any available Synth collateral. This function hardcodes the returned synth as sUSD which we assume is always worth $1 and so also worth 1 isoUSD.

- This function is left as public for ease of exchange rate checking by outside parties. It is a view function and so harmless. The currencyKey for a collateral is bytes32(“synth symbol here”) so for sETH it is found by bytes32(“sETH”).


### openLoan
This function enables a user to open a new loan with any supported collateral. It is intended to be called by anyone in order to open a loan relating to themselves only. 

- The function performs prechecks listed above. Then it verifies that the user has supplied a non-zero collateral quantity and that they actually have greater than or equal to that quantity of collateral in the msg.sender’s address.

- Next the virtual price associated with this collateral is updated and after this has happened the collateral’s values are fetched from the collateralBook contract. 

- Using the currencyKey from this we then call an external contract from Synthetix to verify that the collateral token we are using is allowed to be exchanged now.

- Now the value of the proposed collateral amount is converted to dollars and we calculate the required collateral amount, in dollars, needed to back the proposed loan. We can then verify that the amount of collateral proposed is greater or equal to this.

- We next make calls to the internal functions that handle increasing the collateral and loan of a user.

- We update the mappings that record the collateral the loan holder has sent to the vault and the isoUSD borrowed from the vault then emit an event to record the opening of a new loan. 
openLoan can be used to either open a new loan or increase an existing one.
    
### IncreaseCollateralAmount
This function handles increasing the amount of collateral an existing loan already has to reduce the risk of a user’s debt falling below the liquidation point.

- First prechecks are performed then we verify the user already has a loan with the vault, this is to prevent confusing event logs if there wasn’t already a related loan.

- The virtual price of this collateral token is then updated and once this has happened we can fetch the collateral’s relevant values from the collateralBook contract.

- Using the currencyKey from this we then call an external contract from Synthetix to verify that the collateral token we are using is allowed to be exchanged now.

- Next we check to see if increasing the collateral by the suggested amount will bring the user’s debt above the liquidation point. (Nb: this check isn’t essential but seems fair, otherwise a user could increase the collateral of their loan only to have it all taken from them as now liquidation is profitable for a liquidator). 

- We then call the internal function that handles increasing collateral balances, record the increase in collateral then emit the IncreaseCollateral event to log this.

### closeLoan
This function enables the user to close their loans. It can also be used to return collateral in excess of the opening margin requirements and pay down the borrowed loan separately. 

- The function begins by doing prechecks, then the _closeLoanChecks function detailed before is called.

- The virtual price of this collateral token is then updated and once this has happened we can fetch the collateral’s relevant values from the collateralBook contract.

- Using the currencyKey from this we then call an external contract from Synthetix to verify that the collateral token we are using is allowed to be exchanged now. 

- Using the virtual price it then calculates the total debt the user has incurred for this loan, it verifies that the isoUSD being returned doesn’t exceed this value.

- If the user isn’t completely closing the loan (We consider debt of <$0.001 completely closed to avoid dust amounts) the function then checks that the updated amounts of collateral and loan meet the opening margin requirements. 

- Next we record the internal ledgers of how much collateral the user has posted and how much isoUSD they have borrowed. 

- Once this is done we can call the internal decreaseLoan function to effect these changes before finally emitting the ClosedLoan event to log this.

    

### callLiquidation
This is the way that external users can call a liquidation of any current debt that fails to meet the minimum margin ratio of the collateral token they are using. Users are incentivized by a 5% reward on the liquidation amount. Given optimism transaction fees are low this should incentivize the liquidation of any debt amount greater than around $2.
 

- The function checks the collateral address is valid and the specified loan holder is not the zero address. 

- Then it updates the virtual price of this collateral token and once this has happened we can fetch the collateral’s relevant values from the collateralBook contract. 

- Using the currencyKey from this we then call an external contract from Synthetix to ensure the collateral is active and not frozen.
    

- We fetch the loan holder’s accrued debt and supplied collateral before passing these and the collateral characteristics to the viewLiquidatableAmount. This then returns the quantity of collateral that should be liquidated to return the loan holder’s debt to the minimum margin ratio required for this collateral token. 

- We check the amount is non-zero, else the loan is not liquidatable at all, then we check if it is greater than the loan holder’s collateral. If so we reduce it to their total collateral. This suggests the debt has gone bad and fully reclaiming the debt is impossible. 

- Bad debts should not occur under normal market conditions and will result in a loss to the system if it occurs, the liquidator will however still be incentivized to trigger liquidation by being paid a percentage of the total collateral.

- If the liquidation is the entire collateral supplied we check to see if the debt had gone bad, if so we emit an event BadDebtCleared to log this occurrence and manually reset the loan holder’s loaned isoUSD as with no collateral at stake they would have no incentive to repay it anyway and a non-zero balance would prevent them interacting properly when trying to open new loans. 

- We then  call the internal _liquidate function to continue the process.


