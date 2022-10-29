# Vault_Synths.sol function purposes

## Functions

### pause 
This function allows any accounts with admin role or Pauser to set the system to paused.
    - Both admins and Pausers can pause the system but only admins can unpause the system or set parameter values. This enables the pauser role to be granted to EOAs or members of the multisig independently.
    - This design allows the system to react faster to exploits or detected bugs without also exposing the users to a higher compromised admin account risk. 
    
### unpause
This function allows only accounts with the admin role to unpause the vault system.

### setDailyMax
A daily max of issued loan amount is set by admin calls to this function. 

- The function checks that the daily max is set less than the higher bound of 100 million moUSD (i.e. $100 Million). It then sets the daily max to the inputted value.
    
### setOpenLoanFee
This Admin only function alters the fee charged on opening a loan, allowing for fine control of loan demand. It checks the new loanOpenFee is less than or equal to 10% to prevent Admin abuse/mistake. 
    
### _checkIfCollateralIsActive
For the liquidation system assumptions to function correctly it is essential that when interacted with a synth is not frozen and its market is open. If frozen or untradable then liquidators cannot sell the collateral and so will not desire to execute liquidations.

- For Synths this function verifies that the synth being used for collateral is still tradable for sUSD using the Synthetix exchange contracts. This check entails four parts:
    1. If the Synthetix system as a whole is active.
    2. If exchanging between synths is active.
    3. If exchanging the specific synths involved in this trade is possible.
    4. If either of the specific synths involved is currently suspended.

    
### _getCollateral
When interacting with collateral it is necessary to have a central source of all that collateral’s variables. This function allows us to load in the collateral structure while only assigning variables we actually need in local calls. 
- This is an internal function so all checks to the collateral address it receives must occur prior to using it as an input for this function, it will then get the collateral properties from the collateralBook contract, returning them all in order.

-  it is up to the function calling this to then select those which it actually needs.
    
### _findFees
When minting loans we take an opening fee, this function allows for the easy calculation of the fee and the remainder of the original figure.

### _updateVirtualPrice
To record accumulating interest we maintain a virtual price for each collateral asset, this price is then incremented by the interest per 3 minutes associated to that collateral. 
- This function must be called before interacting with any function that increases or decreases a loan’s size. Otherwise users could use stale virtual prices to abuse the system.

-  First it fetches the related collateral token’s properties then it determines how much time has passed since the virtual price of this collateral was last updated. No checks are made on this timestamp so this function should only be called by trusted inputs. 

- Then it checks we haven’t already updated this collateral’s virtual price in this block and if not it will loop to update the virtual price. Because of the low fee environment this process is kept simple for ease of understanding. 

- If the virtual price has been updated it records this in the collateralBook structure using a function restricted to being callable by the vault only.
    
### _increaseLoan
This function is the only way inside Vault_Synths.sol that moUSD is printed. MoUSD is printed directly to the vault and then transferred to the user and treasury split based on opening loan fees owed. In addition to this it is where the system verifies that the user is not exceeding the daily total system loans issued.  

- This function is internal and  makes few checks on the supplied data it receives so it should only ever be called by functions which have verified the figures being given to the internal function. 
    
### _increaseCollateral
This function is how the system handles increasing the user’s debt collateral. 

- This function is internal and  makes no checks on the supplied data it receives so it should only ever be called by functions which have verified the figures being given to the internal function.
    
### _decreaseLoan
This function handles reducing the loan of a user or returning collateral to the user. It is the only ways to burn MoUSD in Vault_Synths.sol.

- This function is internal and  makes no checks on the supplied data it receives so it should only ever be called by functions which have verified the figures being given to the internal function. 

- It can reduce a users debt by burning moUSD they hold and/or send back collateral to the user from a debt they already have.

- Note the function does not make use of the ERC20 transferFrom function due to Vault.sol contract size being too big if it does. This means block scanners such as Etherscan will only detect the movement of collateral when looking at these transactions.
    
### _closeLoanChecks
This function handles checks made by closeLoan, it is required due to the stack depth of closeLoan.

- It checks the user originally posted as much or more collateral than they’re requesting to be returned to them and that they have sufficient moUSD to be returned to the vault for burning.
    
### priceCollateralToUSD
This function allows us to price any collateral in USD.
In order to use the Synthetix pricing system for the value of a Synth collateral it is necessary for us to call the Synthetix exchange rate for any available Synth collateral. This function hardcodes the returned synth as sUSD which we assume is always worth $1 and so also worth 1 moUSD.

- This function is left as public for ease of exchange rate checking by outside parties. It is a view function and so harmless. The currencyKey for a collateral is bytes32(“synth symbol here”) so for sETH it is found by bytes32(“sETH”).


### openLoan
This function enables a user to open a new loan with any supported collateral. It is intended to be called by anyone in order to open a loan relating to themselves only. 

- The function performs prechecks listed above. Then it verifies that the user has supplied a non-zero collateral quantity and that they actually have greater than or equal to that quantity of collateral in the msg.sender’s address.

- Next the virtual price associated with this collateral is updated and after this has happened the collateral’s values are fetched from the collateralBook contract. 

- Using the currencyKey from this we then call an external contract from Synthetix to verify that the collateral token we are using is allowed to be exchanged now.

- Now the value of the proposed collateral amount is converted to dollars and we calculate the required collateral amount, in dollars, needed to back the proposed loan. We can then verify that the amount of collateral proposed is greater or equal to this.

- We next make calls to the internal functions that handle increasing the collateral and loan of a user.

- We update the mappings that record the collateral the loan holder has sent to the vault and the moUSD borrowed from the vault then emit an event to record the opening of a new loan. 
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

- Using the virtual price it then calculates the total debt the user has incurred for this loan, it verifies that the moUSD being returned doesn’t exceed this value.

- If the user isn’t completely closing the loan (We consider debt of <$0.001 completely closed to avoid dust amounts) the function then checks that the updated amounts of collateral and loan meet the opening margin requirements. 

- Next we record the internal ledgers of how much collateral the user has posted and how much moUSD they have borrowed. 

- Once this is done we can call the internal decreaseLoan function to effect these changes before finally emitting the ClosedLoan event to log this.

    
### _liquidate
This is the internal function that continues the liquidation calulations due to a stack-too-deep error.

- It checks if the sum being repaid is for loan principle or if some relates to the interest charged on the loan

- If it is just loan Principle we reduce moUSDLoaned by this amount

- If some interest is paid then the loan principle must be fully paid so record the difference of the moUSDReturned and principle as interestPaid then we set moUSDLoaned to zero. 

- As this is a liquidation if  moUSDLoanAndInterest is non-zero we know that the liquidation was partial only. And so we update the moUSDLoanAndInterest map to reflect this repayment. 

- Else if the liquidition is a full one, we know there is a bad debt and so we clear the moUSDLoaned mapping to wipe any remaining user debt on this loan. 

- The user's supplied collateral is decremented by the quantity being sent to the liquidator 

- It emits the Liquidation event to log who was liquidated, by whom and  how much of which collateral was liquidated. 

- Finally we pass control to the _decreaseLoan function to handle the transfer of moUSD and collateral.
    
### viewLiquidatableAmount
It is necessary to have a function that will inform users if any debts are liquidatable. This function takes in the state of a user loan and determines if it is below the liquidation point. This function is also then used internally for the callLiquidation function to ensure that the maths is consistent across the contract. 

- Details of how the maths equation is derived are included in the appendix, no checks are made by this function and so if called internally the data is is passed must be checked first.

### callLiquidation
This is the way that external users can call a liquidation of any current debt that fails to meet the minimum margin ratio of the collateral token they are using. Users are incentivized by a 5% reward on the liquidation amount. Given optimism transaction fees are low this should incentivize the liquidation of any debt amount greater than around $2.
 

- The function checks the collateral address is valid and the specified loan holder is not the zero address. 

- Then it updates the virtual price of this collateral token and once this has happened we can fetch the collateral’s relevant values from the collateralBook contract. 

- Using the currencyKey from this we then call an external contract from Synthetix to ensure the collateral is active and not frozen.
    

- We fetch the loan holder’s accrued debt and supplied collateral before passing these and the collateral characteristics to the viewLiquidatableAmount. This then returns the quantity of collateral that should be liquidated to return the loan holder’s debt to the minimum margin ratio required for this collateral token. 

- We check the amount is non-zero, else the loan is not liquidatable at all, then we check if it is greater than the loan holder’s collateral. If so we reduce it to their total collateral. This suggests the debt has gone bad and fully reclaiming the debt is impossible. 

- Bad debts should not occur under normal market conditions and will result in a loss to the system if it occurs, the liquidator will however still be incentivized to trigger liquidation by being paid a percentage of the total collateral.

- If the liquidation is the entire collateral supplied we check to see if the debt had gone bad, if so we emit an event BadDebtCleared to log this occurrence and manually reset the loan holder’s loaned moUSD as with no collateral at stake they would have no incentive to repay it anyway and a non-zero balance would prevent them interacting properly when trying to open new loans. 

- We then  call the internal _liquidate function to continue the process.


