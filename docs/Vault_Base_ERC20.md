# Vault_Base_ERC20 function purposes
This abstract contract implements common core functions present in both Vault_Lyra and Vault_Synths as well as outlining the interfaces that loan interaction functions such as `openLoan()` and `closeLoan()` take.

## functions


### pause 
This function allows any accounts with admin role or Pauser to set the system to paused.
    - Both admins and Pausers can pause the system but only admins can unpause the system or set parameter values. This enables the pauser role to be granted to EOAs or members of the multisig independently.
    - This design allows the system to react faster to exploits or detected bugs without also exposing the users to a higher compromised admin account risk. 
    
### unpause
This function allows only accounts with the admin role to unpause the vault system.


### setDailyMax
A daily max of issued loan amount is set by admin calls to this function. 

- The function checks that the daily max is set less than the higher bound of 100 million isoUSD (i.e. $100 Million). It then sets the daily max to the inputted value.
    
### setOpenLoanFee
This Admin only function alters the fee charged on opening a loan, allowing for fine control of loan demand. It checks the new loanOpenFee is less than or equal to 10% to prevent Admin abuse/mistake. 
    
### proposeTreasury
This function allows Admins only to start the two step process of changing the address where loan fees are sent. It contains a basic zero address check to ensure we do not set the `treasury` to the zero address. It then records the new treasury address and the timestamp at which the change can be enacted. After calling this function the treasury active should still be the pre-existing treasury. 

### setTreasury
This function allows Admins only to finish the transfer of the `treasury` address to the address stored in `pendingTreasury`. First it checks that the current block timestamp is past the update boundary time. This timelock is to ensure that users and the development team can react to the change. Next we check the `pendingTreasury` address is not the zero address. This prevents calling `setTreasury` when `proposeTreasury` has not already been called. Finally it emits an event to record the old and new `treasury` addresses then changes to the new `treasury` address.

### _checkIfCollateralIsActive
see specific Vault implementation.

### _checkDailyMaxLoans
Each Vault has a dailyMax, if the total amount of  isoUSD borrowed exceeds this the call will revert. This is a measure intended to prevent the value of any particular vault from growing too fast and to help protect against any potential exploits which require large trades to perform. 
First it checks if the dayCounter has passed to a new day, if so we reset the `dailyTotal` and update the `dayCounter` to the current timestamp. If not then we just add the new loan amount to the existing `dailyTotal`. We then check if the `dailyTotal` exceeds `dailyMax` and revert if so.

### _collateralExists
Originally a modifier (now an internal function due to code size limitations) this function is called by any function that alters a loan. It verifies that the collateral address given to us by the user is a valid collateral. 

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
This function is the only way inside Vault_Synths.sol that isoUSD is printed. isoUSD is printed directly to the vault and then transferred to the user and treasury split based on opening loan fees owed. In addition to this it is where the system verifies that the user is not exceeding the daily total system loans issued.  

- This function is internal and  makes few checks on the supplied data it receives so it should only ever be called by functions which have verified the figures being given to the internal function. 
    
### _increaseCollateral
This function is how the system handles increasing the user’s debt collateral. 

- This function is internal and  makes no checks on the supplied data it receives so it should only ever be called by functions which have verified the figures being given to the internal function.
    
### _decreaseLoan
This function handles reducing the loan of a user or returning collateral to the user. It is the only ways to burn isoUSD in Vault_Synths.sol.

- This function is internal and  makes no checks on the supplied data it receives so it should only ever be called by functions which have verified the figures being given to the internal function. 

- It can reduce a users debt by burning isoUSD they hold and/or send back collateral to the user from a debt they already have.

- Note the function does not make use of the ERC20 transferFrom function due to Vault.sol contract size being too big if it does. This means block scanners such as Etherscan will only detect the movement of collateral when looking at these transactions.

    
### _closeLoanChecks
This function handles checks made by closeLoan, it is required due to the stack depth of closeLoan.

- It checks the user originally posted as much or more collateral than they’re requesting to be returned to them and that they have sufficient isoUSD to be returned to the vault for burning.

### priceCollateralToUSD
see specific Vault implementation.

### openLoan
see specific Vault implementation.

### increaseCollateralAmount
see specific Vault implementation.

### closeLoan
see specific Vault implementation.

### _liquidate
This is the internal function that continues the liquidation calulations due to a stack-too-deep error.

- It checks if the sum being repaid is for loan principle or if some relates to the interest charged on the loan

- If it is just loan Principle we reduce isoUSDLoaned by this amount

- If some interest is paid then the loan principle must be fully paid so record the difference of the isoUSDReturned and principle as interestPaid then we set isoUSDLoaned to zero. 

- As this is a liquidation if  isoUSDLoanAndInterest is non-zero we know that the liquidation was partial only. And so we update the isoUSDLoanAndInterest map to reflect this repayment. 

- Else if the liquidition is a full one, we know there is a bad debt and so we clear the isoUSDLoaned mapping to wipe any remaining user debt on this loan. 

- The user's supplied collateral is decremented by the quantity being sent to the liquidator 

- It emits the Liquidation event to log who was liquidated, by whom and  how much of which collateral was liquidated. 

- Finally we pass control to the _decreaseLoan function to handle the transfer of isoUSD and collateral.
    
### viewLiquidatableAmount
It is necessary to have a function that will inform users if any debts are liquidatable. This function takes in the state of a user loan and determines if it is below the liquidation point. This function is also then used internally for the callLiquidation function to ensure that the maths is consistent across the contract. 

- Details of how the maths equation is derived are included in the appendix, no checks are made by this function and so if called internally the data is is passed must be checked first.



    
