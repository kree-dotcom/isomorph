# Vault_Lyra.sol function purposes

## Functions

### pause 
This function allows any accounts with admin role or Pauser to set the system to paused.
    - Both admins and Pausers can pause the system but only admins can unpause the system or set parameter values. This enables the pauser role to be granted to EOAs or members of the multisig independently. 
    - This design allows the system to react faster to exploits or detected bugs without also exposing the users to a higher compromised admin account risk. 
    
### unpause
This function allows only accounts with the admin role to unpause the system.

### setDailyMax
A daily max of issued loan amount is set by admin calls to this function. 
    - The function checks that the daily max is set less than the higher bound of 100 million moUSD (i.e. $100 Million). It then sets the daily max to the inputted value.
   
### setOpenLoanFee
The openLoanFee is charged whenever opening or increasing an existing loan. As this is an important mechanism to control loan demand we have an ADMIN only function to set it's value. Because this only occurs to new loans it is not timelocked, it contains a sanity check that the new fee charged is not greater than 10%.


### _checkIfCollateralIsActive
For the liquidation system assumptions to function correctly it is essential that when interacted with Lyra LP tokens their value is not stale. If it is stale then liquidators cannot sell the collateral and so will not desire to execute liquidations and the wrong value will be used for altering loans.

    - For Lyra LP tokens we check the function “getTokenPriceWithCheck()“ for the LiquidityPool related to this Liquidity Provider token. This tells us two things:
    1. isStale this tells us if the greeks have been updated recently. If they have not then it is possible that the value of the liquidity Provider Tokens is wrong and so it is dangerous to interact with loans based on their value.
    2. CircuitBreakerExpiry, this tells us if any of the Lyra circuit breakers (Details here https://docs.lyra.finance/developers/parameters/gwav-parameters#iv-skewvariancecbtimeout and LiquidityCBTimeout below) have been triggered recently and are cooling down. During the cooldown period withdrawals and deposits of LP tokens are restricted and so it can be dangerous to issue new loans. 
    
### _getCollateral
When interacting with collateral it is necessary to have a central source of all that collateral’s variables. This function allows us to load in the collateral structure while only assigning variables we actually need in local calls. 
    - This is an internal function so all checks to the collateral address it receives must occur prior to using it as an input for this function, it will then get the collateral properties from the collateralBook contract, returning them all in order.
    -  it is up to the function calling this to then select those which it actually needs.

### getWithdrawalFee 
Because the withdrawalFee of a lyra LP pool can vary we must fetch it each time it is needed to ensure we use an accurate value. LP tokens are devalued by this as a safety measure as any liquidation would include selling the collateral and so should factor in that cost to ensure it is profitable. 

### _findFees
When minting loans we take an opening fee, this function allows for the easy calculation of the fee and the remainder of the original figure.

### _updateVirtualPrice
To record accumulating interest we maintain a virtual price for each collateral asset, this price is then incremented by the interest per 3 minutes associated to that collateral. 
    - This function must be called before interacting with any function that increases or decreases a loan’s size. Otherwise users could use stale virtual prices to abuse the system.
    -  First it fetches the related collateral token’s properties then it determines how much time has passed since the virtual price of this collateral was last updated. No checks are made on this timestamp so this function should only be called by trusted inputs. 
    - Then it checks we haven’t already updated this collateral’s virtual price in this block and if not it will loop to update the virtual price. Because of the low fee environment this process is kept simple for ease of understanding. 
    - If the virtual price has been updated it records this in the collateralBook structure using a function restricted to being callable by the vault only.
    
### _increaseLoan
This function is the only way inside Vault_Lyra.sol that moUSD is printed. MoUSD is printed directly to the vault and then transferred to the user and treasury split based on opening loan fees owed. In addition to this it is where the system verifies that the user is not exceeding the daily total system loans issued.  
    - This function is internal and  makes few checks on the supplied data it receives so it should only ever be called by functions which have verified the figures being given to the internal function. 
    
### _increaseCollateral
This function is how the system handles increasing the user’s debt collateral. 
    - This function is internal and  makes no checks on the supplied data it receives so it should only ever be called by functions which have verified the figures being given to the internal function.
    
### _decreaseLoan
This function handles reducing the loan of a user or returning collateral to the user. It is the only way to burn MoUSD in Vault_Lyra.sol.
    - This function is internal and  makes no checks on the supplied data it receives so it should only ever be called by functions which have verified the figures being given to the internal function. 
    - It can reduce a users debt by burning moUSD and/or send back collateral to the user from a loan they already have.
    
### _closeLoanChecks
This function handles checks made by closeLoan, it is required due to the stack depth of closeLoan.
    - It checks the user originally posted as much or more collateral than they’re requesting to be returned to them and that they have sufficient moUSD to be returned to the vault for burning.
    
### priceCollateralToUSD
This function allows us to price any collateral in USD.
As Lyra is based on Synthetix it shows value in sUSD, for simplicity we currently fix sUSD's value at $1 though in practice it has been known to vary from this amount by a few percent.
    - This function is left as public for ease of exchange rate checking by outside parties. It is a view function and so harmless. 
-  we use the LiquidityPool contract related to the Liquidity Provider token. This contract has a “getTokenPrice()” function which enables us to price any non-stale LP token. Any call to PriceCollateralToUSD must be preceded by a “_checkifCollateralIsActive()” check as the returned prices are meaningless if the collateral is inactive or stale.

### openLoan
This function enables a user to open a new loan with any supported collateral. It is intended to be called by anyone in order to open a loan relating to themselves only. 
    - The function first checks the supplied collateral is a valid collateral address and that the user has greater than or equal to that quantity of collateral in their possession.
    - Next the virtual price associated with this collateral is updated and after this has happened the collateral’s values are fetched from the collateralBook contract. 
    - Using the currencyKey from this we then call an external contract from Lyra to verify that the collateral token we are using is not stale.
    - Now the value of the proposed collateral amount is converted to dollars and we calculate the required collateral amount, in dollars, needed to back the proposed loan. We can then verify that the amount of collateral proposed is greater or equal to this.

    - We update the mappings that record the collateral the loan holder has sent to the vault and the moUSD borrowed from the vault then emit an event to record the opening of a new loan or increasing of an existing one. 
    - Finally we make calls to the internal functions that handle increasing the collateral and loan of a user by transfering from and to the user. 

openLoan can be used to either open a new loan or increase an existing one.
    
### IncreaseCollateralAmount
This function handles increasing the amount of collateral an existing loan already has to reduce the risk of a user’s debt falling below the liquidation point.
    - First a collateral existance precheck is performed then we verify the user already has a loan with the vault, this is to prevent confusing event logs if there wasn’t already a related loan.
   - We check the collateral being added is non-zero and that the user has greater than or equal to that quantity of collateral in their possession.
    - The virtual price of this collateral token is then updated and once this has happened we can fetch the collateral’s relevant values from the collateralBook contract.
     - Using the currencyKey from this we then call an external contract from Lyra to verify that the collateral token we are using is not stale.
    - Next we check to see if increasing the collateral by the suggested amount will bring the user’s debt above the liquidation point. (Nb: this check isn’t essential but seems fair, otherwise a user could increase the collateral of their loan only to have it all taken from them as now liquidation is profitable for a liquidator). 
    - We record the increase in collateral then emit the IncreaseCollateral event to log this.
     - We then call the internal function that handles increasing collateral balances by transfering the collateral tokens from the user.

### closeLoan
This function enables the user to close their loans. It can also be used to return collateral in excess of the opening margin requirements and pay down the borrowed loan separately. 
    - The function begins by doing prechecks, then the _closeLoanChecks function detailed before is called.
    - The virtual price of this collateral token is then updated and once this has happened we can fetch the collateral’s relevant values from the collateralBook contract.
    - Using the currencyKey from this we then call an external contract from Lyra to verify that the collateral token we are using is not stale.
    - Using the virtual price it then calculates the total debt the user has incurred for this loan, it verifies that the moUSD being returned doesn’t exceed this value.
    - If the user isn’t completely closing the loan (We consider debt of <$0.001 completely closed to avoid dust amounts) the function then checks that the updated amounts of collateral and loan meet the opening margin requirements. 
   - Because we repay the loan principle prior to the loan interest we determine if the full loan principle has been repaid, if so then any excess repaid over this is interest being repaid, the interest repaid is sent to the Treasury not burnt and so we must record it seperately. 
    - Next we update the internal ledgers of how much collateral the user still has posted and how much moUSD total they have to repay. 
    - Once this is done we emit the ClosedLoan event.
    - Finally we transfer any returning collateral back to the user and transfer any moUSD being repaid to the vault by calling _decreaseLoan.

    
### _liquidate
This is the internal function that continues the liquidation calulations due to a stack-too-deep error.
    - It checks if the sum being repaid is for loan principle or if some relates to the interest charged on the loan
     - If it is just loan Principle we reduce moUSDLoaned by this amount
     - If some interest is paid then the loan principle must be fully paid so record the difference of the moUSDReturned and principle as interestPaid then we set moUSDLoaned to zero. 
    - As this is a liquidation if  moUSDLoanAndInterest is already zero then we know we must be handling a bad debt (as with bad debts this is set to zero on line 606) if we are dealing with a bad debt we do not need to update moUSDLoanAndInterest, otherwise we reduce it by the moUSDReturned, adjusted by the virtualPrice scale.
   - If we are dealing with a bad debt we also need to set the loan principle moUSDLoaned mapping to zero now too as the user has no incentive to pay this down if they have been fully liquidated.
   - We reduce the collateralPosted map by the amount being paid to the liquidator.
    - It emits the Liquidation event to log who was liquidated, by whom and  how much of which collateral was liquidated. 
    - Finally we pass control to _decreaseLoan transfering moUSD from the liquidator and sending them the relevant collateral tokens.
    
    
### viewLiquidatableAmount
It is necessary to have a function that will inform users if any debts are liquidatable. This function takes in the state of a user loan and determines if it is below the liquidation point. This function is also then used internally for the callLiquidation function to ensure that the maths is consistent across the contract. 
    - Details of how the maths equation is derived are included in the appendix, no checks are made by this function and so if called internally the data is is passed must be checked first.

### callLiquidation
This is the way that external users can call a liquidation of any current debt that fails to meet the minimum margin ratio of the collateral token they are using. Users are incentivized by a 5% reward on the liquidation amount. Given optimism transaction fees are low this should incentivize the liquidation of any debt amount greater than around $2.
 
    - The function checks the collateral address is valid and the specified loan holder is not the zero address. 
    - Then it updates the virtual price of this collateral token and once this has happened we can fetch the collateral’s relevant values from the collateralBook contract. 
    - Using the currencyKey from this we then call an external contract from Lyra to ensure the collateral's price is not stale and the circuit breakers are not active.
    - We fetch the loan holder’s accrued debt and supplied collateral before passing these and the collateral characteristics to the viewLiquidatableAmount. This then returns the quantity of collateral that should be liquidated to return the loan holder’s debt to the minimum margin ratio required for this collateral token. 
    - We check the amount is non###zero, else the loan is not liquidatable at all, then we check if it is greater than the loan holder’s collateral. If so we reduce it to their total collateral. This suggests the debt has gone bad and fully reclaiming the debt is impossible. 
    - Bad debts should not occur under normal market conditions and will result in a loss to the system if it occurs, the liquidator will however still be incentivized to trigger liquidation by being paid a percentage of the total collateral.
        - If the liquidation is the entire collateral supplied we check to see if the debt had gone bad, if so we emit an event BadDebtCleared to log this occurrence and manually reset the loan holder’s loaned moUSD as with no collateral at stake they would have no incentive to repay it anyway and a non-zero balance would prevent them interacting properly when trying to open new loans. 
    - We then  call the internal _liquidate function to continue the process.




