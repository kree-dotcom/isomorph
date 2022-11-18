# Vault_Velo.sol function purposes

## Functions

### pause 
This function allows any accounts with admin role or Pauser to set the system to paused.
- Both admins and Pausers can pause the system but only admins can unpause the system or set parameter values. This enables the pauser role to be granted to EOAs or members of the multisig independently. 
- This design allows the system to react faster to exploits or detected bugs without also exposing the users to a higher compromised admin account risk. 
    
### unpause
This function allows only accounts with the admin role to unpause the system.

### setDailyMax
A daily max of issued loan amount is set by admin calls to this function. 
- The function checks that the daily max is set less than the higher bound of 100 million isoUSD (i.e. $100 Million). It then sets the daily max to the inputted value.
    
### setOpenLoanFee
This Admin only function alters the fee charged on opening a loan, allowing for fine control of loan demand. It checks the new loanOpenFee is less than or equal to 10% to prevent Admin abuse/mistake. 

### onERC721Received 
This function is required to be able to receive ERC721 tokens. It has no other purpose.

### _checkDailyMaxLoans
An internal function that checks the amount of loans opened each day. This a rate limiting feature than can be relaxed as the system matures. It is intended to limit the impact of any discovered bug that involves opening and closing loans.


### _priceCollateral
An internal function that enables the Vault to value a given depositReceipt token.

- It fetches the pooledTokens mapping from the depositReceipt then passes the returned quantity into depositReceipt's priceLiquidity to receive a USD value of the related NFT.
 
### _totalCollateralValue 
 This function returns the total USD value of all NFTs related to one user's loan in the specified collateral depositReceipt.
 
- It fetches the pooledTokens mapping from the depositReceipt for each related NFT adding them together then it passes the sum into depositReceipt's priceLiquidity to receive a USD value of the related NFTs.
    
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
This function is the only way inside Vault.sol that isoUSD is printed. isoUSD is printed directly to the vault and then transferred to the user and treasury split based on opening loan fees owed. In addition to this it is where the system verifies that the user is not exceeding the daily total system loans issued.  

- This function is internal and  makes few checks on the supplied data it receives so it should only ever be called by functions which have verified the figures being given to the internal function. 
    
### _increaseCollateral
This function is how the system handles increasing the user’s debt collateral. 

- This function is internal and  makes no checks on the supplied data it receives so it should only ever be called by functions which have verified the figures being given to the internal function.
    
### _decreaseLoanOrCollateral
This function handles reducing the loan of a user or returning collateral to the user. It is the only way to burn isoUSD in Vault_Velo.sol.

- This function is internal and  makes no checks on the supplied data it receives so it should only ever be called by functions which have verified the figures being given to the internal function. 

- It can reduce a users debt by transfered and burning isoUSD they hold and/or send back collateral to the user from a debt they already have, the return of collateral is handled by _returnAndSplitNFTs()

### _checkNFTOwnership 
Several external functions rely on the user supplying the NFT ids and the related collateral slots these are held in. Because we cannot trust this data to be correct it is necessary to verify it is right on each call. 

- First we check for the zero id, we disallow this to prevent mapping confusions. 

- Then we load the owner's collateral data and loop through each collateral Id's slot looking for the specified _NFTId if we find it we return the related slot else we return `NOT_OWNED` = 999, given there are only 8 collateral slots per user loan this is a safe way to indicate the supplied Id is not collateral for this user's specified loan. 

### getLonNFTids
This is an external helper function to fetch the id of an NFT relating to a  certain user's loan collateral slot. 
    

### openLoan
This function enables a user to open a new loan with any supported collateral. It is intended to be called by anyone in order to open a loan relating to themselves only. 

- The function performs the _collateralExists check. Then if the user has signaled to add collateral it checks the collateral NFT Id is non-zero.

- It then checks the msg.sender owns the depositReceipt NFT specified and calculates the USD value of the depositReceipt. 

- Next the virtual price associated with this collateral is updated and after this has happened the collateral’s values are fetched from the collateralBook contract. 

- Now that the virtualPrice is up-to-date we read the existing loan and accumulated interest from the mapping 

- we then calculate the maximum possible borrowing amount and the value of existing collateral (if any) to check if the minimum opening margin is met after all relevant adjustments. 

- If the loanholder is adding more collateral we now process the NFT's movement to the Vault.

- After this we also process the increase of the loan, which always occurs on openLoan() calls.
    
- We update the mappings that record the the isoUSD principle borrowed from the vault and the interest + principle.

- Because the collateral is non-fungible we need to record the deposited NFT's id, we load this loan's collateral Ids then cycle through the slots until we find one that is empty, once found we store the new collateral NFT id. If there is not a free slot then openLoan() reverts.

- Finally we emit an event to record the opening of a new loan. 
openLoan can be used to either open a new loan or increase an existing one.
    
    
### IncreaseCollateralAmount
This function handles increasing the amount of collateral an existing loan already has to reduce the risk of a user’s debt falling below the liquidation point.

- First prechecks are performed and we check the NFTId is not zero as this can cause confusion with mappings as the default value.

- Then we verify the user already has a loan with the vault, this is to prevent confusing event logs if there wasn’t already a related loan.

- Further sanity checks: Is the sender the owner of the given NFT and is the value of the given NFT non-zero?

- The virtual price of this collateral token is then updated and once this has happened we can fetch the collateral’s relevant values from the collateralBook contract.

- Next we check to see if increasing the collateral by the suggested amount will bring the user’s debt above the liquidation point. (Nb: this check isn’t essential but seems fair, otherwise a user could increase the collateral of their loan only to have it all taken from them as now liquidation is profitable for a liquidator). 

- We then emit the IncreaseCollateralNFT event to maintain CEI ordering. 

- As NFTs are non-fungible we need to store the deposited NFT's ID in relation to this loan. We check for an empty slot relating to this loan then write the supplied NFT ID to it. If no free slots exist, we revert.

- Finally we call the internal function that handles transfering the specified NFT to the Vault.

### closeLoan
This function enables the user to close their loans. It can also be used to return collateral in excess of the opening margin requirements and pay down the borrowed loan separately. 

- The function begins by checking the supplied collateral is a valid one.

- Next because we rely on the user to supply both NFT IDs and the array slots they are stored in we validate this infomation to prevent abuse. If any details are wrong we revert.

- The virtual price of this collateral token is then updated and once this has happened we can fetch the collateral’s relevant values from the collateralBook contract.

- Using the virtual price it then calculates the total debt the user has incurred for this loan, it verifies that the isoUSD being returned doesn’t exceed this value.

- If the user isn’t completely closing the loan (We consider debt of <=$0.001 completely closed to avoid dust amounts) the function then checks that the updated amounts of collateral and loan meet the opening margin requirements. 

- To determine how to update the owed loan principle and total owed loan (principle & interest, mapping isoUSDLoanAndInterest) we check if the original loan principle is greater (or equal) than the isoUSD being returned. If it is then we only reduce the principle owed.

- If the isoUSD returned is larger than the original loan principle then we also have interest being paid. Interest is treated differently as it is not burned but instead sent to the treasury. If interest is being paid we know the original loan principle must be fulled repaid so we write this value as zero to record it's full repayment. 
 
- Once this is done we can call the internal decreaseLoanOrCollateral function to effect these changes, this function will burn any principle repaid and forward any interestPaid to the treasury.

- Finally we emit the ClosedLoan event, emitting the event here does not strictly follow CEI pattern but should not cause any issues.



### _calculateProposedReturnedCapital

- This internval view function calculates the value of a proposed liquidation by cyclign through the supplied loanNFT ids and summing the prices of each respective NFT. If _partialPercentage is being used (i.e. non-zero and not 100%) then the final slot NFT will have it's value adjusted by the partial percentage given, otherwise the final slot is treated like a normal NFT being fully returned.
    
### _returnAndSplitNFTs
- This internal function handles the return process of collateral NFTs, it starts by taking the collateral address and setting it up as an instance of the ERC721 depositReceipt. 

- Next it loads the user loan's collateral NFTs from storage so that later we can amend these to reflect removals.

- We begin a loop that runs for 8 cycles (the max number of NFT ids that can relate to a single collateral loan). Each cycle does the following:

- check if the slot is being used, if not then the slot should be set to `NOT_OWNED` (999). If the slot is not being used we skip to the next cycle. Else we:

- check if we are looking at the final 8th slot, this slot relates to partial returns so we also check if the partial percentage is being used by checking for a non-zero amount. If partialPercentage is `LOAN_SCALE` then the slot is being used as a normal full liquidation slot so we skip from the partial return logic straight to normal processing. 

- If we are processing a partial return we call split on the related NFT, this breaks off the partialPercentage of the original NFT as a new NFT that is intended to be returned. As the original is kept in the loan as collateral we make no userNFTs id amendments here.

- For full NFT returns we set the slot id to zero to clear it and then transfer the related depositReceipt NFT back to the user.
    
### _liquidate
This is the internal function that continues the liquidation process started in callLiquidation

- To determine how to update the owed loan principle and total owed loan (principle & interest, mapping isoUSDLoanAndInterest) we check if the original loan principle is greater (or equal) than the isoUSD being returned. If it is then we only reduce the principle owed.

- If the isoUSD returned is larger than the original loan principle then we also have interest being paid. Interest is treated differently as it is not burned but instead sent to the treasury. If interest is being paid we know the original loan principle must be fulled repaid so we write this value as zero to record it's full repayment. 

- We check if isoUSDLoanAndInterest is greater than zero. If it is non-zero then we know we need to reduce the recorded loanAndInterest of the loan holder.

-  If it is zero this signals we are dealing with a bad debt as this should be the only situation in which a liquidation results in full repayment of a loan. In this case we need to wipe the original principle the loan holder owed too.
    
- Then we pass control to _decreaseLoanOrCollateral to handle the repayment of isoUSD and sending the NFT collateral to the liquidator as payment for liquidation.

- Finally it emits the LiquidationNFT event to log who was liquidated, by whom and  how much of which collateral was liquidated. 
    
### viewLiquidatableAmount
It is necessary to have a function that will inform users if any debts are liquidatable. This function takes in the state of a user loan and determines if it is below the liquidation point. This function is also then used internally for the callLiquidation function to ensure that the maths is consistent across the contract. 
- Details of how the maths equation is derived are included in the appendix, no checks are made by this function and so if called internally the data is is passed must be checked first.

### callLiquidation
This is the way that external users can call a liquidation of any current debt that fails to meet the liquidation margin ratio of the collateral token they are using. Users are incentivized by a 5% reward on the liquidation amount. Given optimism transaction fees are low this should incentivize the liquidation of any debt amount greater than around $2.
 
- The function performs prechecks that the collateral address provided by the user is valid and the loan holder address is not the zero address.

- Because we rely on the user to supply both NFT IDs and the array slots they are stored in we validate this information to prevent abuse. If any details are wrong we revert.

- Then it updates the virtual price of this collateral token and once this has happened we can fetch the collateral’s relevant values from the collateralBook contract. 

- We fetch the loan holder’s accrued debt and supplied collateral before passing these and the collateral characteristics to the viewLiquidatableAmount. This then returns the quantity of collateral that should be liquidated to return the loan holder’s debt to the minimum margin ratio required for this collateral token. 

- We check the amount is non-zero, else the loan is not liquidatable at all, then we check if it is greater than the loan holder’s collateral. If so we reduce it to their total collateral and adjust the isoUSDreturning as necessary. This suggests the debt has gone bad and fully reclaiming the debt is impossible as proposedLiquidationAmount represents the minimum collateral that needs to be sold in order to return the loan to healthy conditions.
    
- Bad debts should not occur under normal market conditions and will result in a loss to the system if it occurs, the liquidator will however still be incentivized to trigger liquidation by redeeming the loan collateral at a discount.
    
- Then we emit an event BadDebtClearedNFT to log this occurrence and manually reset the loan holder’s loaned isoUSD as with no collateral at stake they would have no incentive to repay it anyway and a non-zero balance would prevent them interacting properly when trying to open new loans.
        
- Finally we call _liquidate to continue checks (stack too deep for a single function) and process the token transfers.
 



