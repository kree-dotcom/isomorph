// SPDX-License-Identifier: MIT
// Vault_Lyra.sol for isomorph.loans
// Bug bounties available

pragma solidity =0.8.9; 
pragma abicoder v2;

// External Lyra interface
import "./helper/interfaces/ILiquidityPoolAvalon.sol";
import "./helper/interfaces/IMultiDistributor.sol";

//External OpenZeppelin dependancy
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

//Vault Base for common functions
import "./Vault_Base_ERC20.sol";

//Lyra stkLyra & OP reward claimer
import "./RewardClaimer.sol";
import "./interfaces/IRewardClaimer.sol";


contract Vault_Lyra is Vault_Base_ERC20, ReentrancyGuard{

    using SafeERC20 for IERC20;
    
    //collateral address => user address => rewardClaimer address
    mapping(address => mapping(address => address)) public rewardClaimers;

    constructor(
        address _isoUSD, //isoUSD address
        address _treasury, //treasury address
        address _collateralBook //collateral structure book address
        ){
        require(_isoUSD != address(0), "Zero Address used isoUSD");
        require(_treasury != address(0), "Zero Address used Treasury");
        require(_collateralBook != address(0), "Zero Address used Collateral");
        isoUSD = IisoUSDToken(_isoUSD);
        treasury = _treasury;
        collateralBook = ICollateralBook(_collateralBook);
        _setupRole(ADMIN_ROLE, msg.sender);
        _setupRole(PAUSER_ROLE, msg.sender);
       
    } 
    
    

    
    /**
        Internal helper and check functions
     */

    /// @dev process for Lyra LP assets
    /// @dev this uses the liquidity Pool associated with the LP token to verify the circuit breaker is not active
    /// @dev to be overly cautious if the CB is active we revert
    /// @notice if any of them aren't the function will revert.
    /// @param _currencyKey the code used by synthetix to identify different synths, linked in collateral structure to collateral address
    function _checkIfCollateralIsActive(bytes32 _currencyKey) internal view override {
            
             //Lyra LP tokens use their associated LiquidityPool to check if they're active
             ILiquidityPoolAvalon LiquidityPool = ILiquidityPoolAvalon(collateralBook.liquidityPoolOf(_currencyKey));
             bool isStale;
             uint circuitBreakerExpiry;
             //ignore first output as this is the token price and not needed yet.
             (, isStale, circuitBreakerExpiry) = LiquidityPool.getTokenPriceWithCheck();
             require( !(isStale), "Global Cache Stale, can't trade");
             require(circuitBreakerExpiry < block.timestamp, "Lyra Circuit Breakers active, can't trade");
    }
    

    /// @param _liquidityPool the address of the liquidityPool relating to the Lyra collateral we're using
    /// @notice there is a withdrawal fee for Lyra LPs, so we depreciate LP tokens by this to get the fair value
    /// @notice because the withdrawal fee is dynamic we must fetch it on each LP token valuation in case it's changed
    function _getWithdrawalFee(ILiquidityPoolAvalon _liquidityPool) internal view returns(
        uint256 ){
        ILiquidityPoolAvalon.LiquidityPoolParameters memory params = _liquidityPool.getLpParams();
        return ( params.withdrawalFee );
    }

    /// @dev this overrides the default implementation in Vault_Base_ERC20 to sent LP tokens directly to rewardClaimer.
    /// @dev internal function used to increase user collateral on loan.
    /// @param _collateral the ERC20 compatible collateral to use, already set up in another function
    /// @param _colAmount the amount of collateral to be transfered to the vault. 
    function _increaseCollateral(IERC20 _collateral, uint256 _colAmount) internal override {
        address rewardClaimer = rewardClaimers[address(_collateral)][msg.sender];
        if(rewardClaimer == address(0)){
            rewardClaimer = address(new RewardClaimer(msg.sender, address(this), address(_collateral), collateralBook));
            rewardClaimers[address(_collateral)][msg.sender] = rewardClaimer;
        }
        _collateral.safeTransferFrom(msg.sender, rewardClaimer, _colAmount);
        
    }

    /// @dev internal function used to move LP Tokens back to the vault from the claimer contract.
    /// @param _collateral the ERC20 compatible collateral address to be returned to the vault
    /// @param _amount the amount of collateral to be transfered to the vault. 
    function _redeemLPTokens(address _collateral, uint256 _amount, address _loanHolder) internal {
        //a user must always have called _increaseCollateral before getting here and so should always have a rewardClaimer address
        IRewardClaimer rewardClaimer = IRewardClaimer(rewardClaimers[address(_collateral)][_loanHolder]);
        rewardClaimer.withdraw(_amount);
    }


    /**
        Public functions 
    */


    //isoUSD is assumed to be valued at $1 by all of the system to avoid oracle attacks. 
    /// @param _currencyKey code used by the system to identify each collateral
    /// @param _amount quantity of collateral to price into sUSD
    /// @return returns the value of the given collateral in sUSD which is assumed to be pegged at $1.
    function priceCollateralToUSD(bytes32 _currencyKey, uint256 _amount) public view override returns(uint256){
         //The LiquidityPool associated with the LP Token is used for pricing
        ILiquidityPoolAvalon LiquidityPool = ILiquidityPoolAvalon(collateralBook.liquidityPoolOf(_currencyKey));
        //we have already checked for stale greeks so here we call the basic price function.
        uint256 tokenPrice = LiquidityPool.getTokenPrice();          
        uint256 withdrawalFee = _getWithdrawalFee(LiquidityPool);
        uint256 USDValue  = (_amount * tokenPrice) / LOAN_SCALE;
        //we remove the Liquidity Pool withdrawalFee 
        //as there's no way to remove the LP position without paying this.
        uint256 USDValueAfterFee = USDValue * (LOAN_SCALE- withdrawalFee)/LOAN_SCALE;
        return(USDValueAfterFee);
    }

    /**
        External user loan interaction functions
     */


     /**
      * @notice Only Vaults can mint isoUSD.
      * @dev Mints 'USDborrowed' amount of isoUSD to vault and transfers to msg.sender and emits transfer event.
      * @param _collateralAddress address of collateral token being used.
      * @param _colAmount amount of collateral tokens being used.
      * @param _USDborrowed amount of isoUSD to be minted, it is then split into the amount sent and the opening fee.
     **/
    function openLoan(
        address _collateralAddress,
        uint256 _colAmount,
        uint256 _USDborrowed
        ) external override whenNotPaused nonReentrant
        {
        _collateralExists(_collateralAddress);
        require(!collateralBook.collateralPaused(_collateralAddress), "Paused collateral!");
        IERC20 collateral = IERC20(_collateralAddress);
        
        require(collateral.balanceOf(msg.sender) >= _colAmount, "User lacks collateral quantity!");
        //make sure virtual price is related to current time before fetching collateral details
        //slither-disable-next-line reentrancy-vulnerabilities-1
        _updateVirtualPrice(block.timestamp, _collateralAddress);  
        
        (   
            bytes32 currencyKey,
            uint256 minOpeningMargin,
            ,
            ,
            ,
            uint256 virtualPrice,
            
        ) = _getCollateral(_collateralAddress);
        //check for frozen or paused collateral
        _checkIfCollateralIsActive(currencyKey);
        //make sure the total isoUSD borrowed doesn't exceed the opening borrow margin ratio
        uint256 colInUSD = priceCollateralToUSD(currencyKey, _colAmount + collateralPosted[_collateralAddress][msg.sender]);
        uint256 totalUSDborrowed = _USDborrowed +  (isoUSDLoanAndInterest[_collateralAddress][msg.sender] * virtualPrice)/LOAN_SCALE;
        uint256 borrowMargin = (totalUSDborrowed * minOpeningMargin) / LOAN_SCALE;
        require(colInUSD >= borrowMargin, "Minimum margin not met!");

        //update mappings with new loan amounts
        collateralPosted[_collateralAddress][msg.sender] = collateralPosted[_collateralAddress][msg.sender] + _colAmount;
        isoUSDLoaned[_collateralAddress][msg.sender] = isoUSDLoaned[_collateralAddress][msg.sender] + _USDborrowed;
        isoUSDLoanAndInterest[_collateralAddress][msg.sender] = isoUSDLoanAndInterest[_collateralAddress][msg.sender] + ((_USDborrowed * LOAN_SCALE) / virtualPrice);
        
        emit OpenOrIncreaseLoan(msg.sender, _USDborrowed, currencyKey, _colAmount);

        //Now all effects are handled, transfer the assets so we follow CEI pattern
        _increaseCollateral(collateral, _colAmount);
        _increaseLoan(_USDborrowed, _collateralAddress);
        
        
    }


    /**
      * @dev Increases collateral supplied against an existing loan. 
      * @notice Checks adding the collateral will keep the user above liquidation, 
      * @notice this debatable check isn't technically needed but feels fairer to end users.
      * @param _collateralAddress address of collateral token being used.
      * @param _colAmount amount of collateral tokens being used.
     **/
    function increaseCollateralAmount(
        address _collateralAddress,
        uint256 _colAmount
        ) external override nonReentrant
        {
        _collateralExists(_collateralAddress);
        require(collateralPosted[_collateralAddress][msg.sender] > 0, "No existing collateral!"); //feels like semantic overloading and also problematic for dust after a loan is 'closed'
        require(_colAmount > 0 , "Zero amount"); //Not strictly needed, prevents event spamming though
        //make sure virtual price is related to current time before fetching collateral details
        //slither-disable-next-line reentrancy-vulnerabilities-1
        _updateVirtualPrice(block.timestamp, _collateralAddress);
        IERC20 collateral = IERC20(_collateralAddress);
        require(collateral.balanceOf(msg.sender) >= _colAmount, "User lacks collateral amount");
        (   
            bytes32 currencyKey,
            ,
            uint256 liquidatableMargin,
            ,
            ,
            uint256 virtualPrice,
            
        ) = _getCollateral(_collateralAddress);
        //check for frozen or paused collateral
        _checkIfCollateralIsActive(currencyKey);
        //update mapping with new collateral amount
        collateralPosted[_collateralAddress][msg.sender] = collateralPosted[_collateralAddress][msg.sender] + _colAmount;
        emit IncreaseCollateral(msg.sender, currencyKey, _colAmount);
        //Now all effects are handled, transfer the collateral so we follow CEI pattern
        _increaseCollateral(collateral, _colAmount);
        
    }


     /**
      * @notice Only Vault can destroy isoUSD.
      * @dev destroys USDreturned of isoUSD held by caller, returns user collateral, close debt 
      * @dev if debt remains, checks minimum collateral ratio is upheld 
      * @dev if cost of a transaction can be <$0.01 YOU MUST UPDATE TENTH_OF_CENT check otherwise users can open microloans and close, withdrawing collateral without repaying. 
      * @param _collateralAddress address of collateral token being used.
      * @param _collateralToUser amount of collateral tokens being returned to user.
      * @param _USDToVault amount of isoUSD to be burnt.
     **/

    function closeLoan(
        address _collateralAddress,
        uint256 _collateralToUser,
        uint256 _USDToVault
        ) external override nonReentrant
        {
        _collateralExists(_collateralAddress);
        _closeLoanChecks(_collateralAddress, _collateralToUser, _USDToVault);
        //make sure virtual price is related to current time before fetching collateral details
        //slither-disable-next-line reentrancy-vulnerabilities-1
        _updateVirtualPrice(block.timestamp, _collateralAddress);
        (   
            bytes32 currencyKey,
            uint256 minOpeningMargin,
            ,
            ,
            ,
            uint256 virtualPrice,
            
        ) = _getCollateral(_collateralAddress);
        
        uint256 isoUSDdebt = (isoUSDLoanAndInterest[_collateralAddress][msg.sender] * virtualPrice) / LOAN_SCALE;
        if(isoUSDdebt < _USDToVault){
            _USDToVault = isoUSDdebt;
        }
        uint256 outstandingisoUSD = isoUSDdebt - _USDToVault;
        if((outstandingisoUSD > 0) && (_collateralToUser > 0)){  //check for leftover debt
            //check for frozen or paused collateral
            _checkIfCollateralIsActive(currencyKey);
            uint256 collateralLeft = collateralPosted[_collateralAddress][msg.sender] - _collateralToUser;
            uint256 colInUSD = priceCollateralToUSD(currencyKey, collateralLeft); 
            uint256 borrowMargin = (outstandingisoUSD * minOpeningMargin) / LOAN_SCALE;
            require(colInUSD >= borrowMargin , "Remaining debt fails to meet minimum margin!");
        }

        //record paying off loan principle before interest
        //slither-disable-next-line uninitialized-local-variables
        uint256 interestPaid;
        uint256 loanPrinciple = isoUSDLoaned[_collateralAddress][msg.sender];
        if( loanPrinciple >= _USDToVault){
            //pay off loan principle first
            isoUSDLoaned[_collateralAddress][msg.sender] = loanPrinciple - _USDToVault;
        }
        else{
            interestPaid = _USDToVault - loanPrinciple;
            //loan principle is fully repaid so record this.
            isoUSDLoaned[_collateralAddress][msg.sender] = 0;
        }

        //update mappings with reduced amounts
        isoUSDLoanAndInterest[_collateralAddress][msg.sender] = isoUSDLoanAndInterest[_collateralAddress][msg.sender] - ((_USDToVault * LOAN_SCALE) / virtualPrice);
        collateralPosted[_collateralAddress][msg.sender] = collateralPosted[_collateralAddress][msg.sender] - _collateralToUser;
        emit ClosedLoan(msg.sender, _USDToVault, currencyKey, _collateralToUser);
        //Now all effects are handled, transfer the assets so we follow CEI pattern
        _redeemLPTokens(_collateralAddress, _collateralToUser, msg.sender);
        _decreaseLoan(_collateralAddress, _collateralToUser, _USDToVault, interestPaid);
        }
    
    

    /**
        Liquidation functions


     /**
      * @notice Anyone can liquidate any other undercollateralised loan.
      * @notice The max acceptable liquidation quantity is calculated using viewLiquidatableAmount
      * @dev checks that partial liquidation would be insufficient to recollaterize the loanHolder's debt 
      * @dev caller is paid 1e18 -`LIQUIDATION_RETURN` as reward for calling the liquidation.
      * @dev In the event of full liquidation being insufficient the leftover debt is written off and an event tracking this is emitted.
      * @param _loanHolder address of loanee being liquidated.
      * @param _collateralAddress address of collateral token being used.
     **/
        
        function callLiquidation(
            address _loanHolder,
            address _collateralAddress
        ) external override nonReentrant
        {   
            _collateralExists(_collateralAddress);
            require(_loanHolder != address(0), "Zero address used"); 
             //make sure virtual price is related to current time before fetching collateral details
            //slither-disable-next-line reentrancy-vulnerabilities-1
            _updateVirtualPrice(block.timestamp, _collateralAddress);
            (
                bytes32 currencyKey,
                ,
                uint256 liquidatableMargin,
                ,
                ,
                uint256 virtualPrice,
                
            ) = _getCollateral(_collateralAddress);
            //check for frozen or paused collateral
            _checkIfCollateralIsActive(currencyKey);
            //check how much of the specified loan should be closed
            uint256 isoUSDBorrowed = (isoUSDLoanAndInterest[_collateralAddress][_loanHolder] * virtualPrice) / LOAN_SCALE;
            uint256 totalUserCollateral = collateralPosted[_collateralAddress][_loanHolder];
            uint256 currentPrice = priceCollateralToUSD(currencyKey, LOAN_SCALE); //assumes LOAN_SCALE = 1 ether, i.e. one unit of collateral!
            uint256 liquidationAmount = viewLiquidatableAmount(totalUserCollateral, currentPrice, isoUSDBorrowed, liquidatableMargin);
            require(liquidationAmount > 0 , "Loan not liquidatable");
            //if complete liquidation falls short of recovering the position we settle for complete liquidation
            if(liquidationAmount > totalUserCollateral){
                liquidationAmount = totalUserCollateral;
            }
            uint256 isoUSDreturning = liquidationAmount*currentPrice*LIQUIDATION_RETURN/LOAN_SCALE/LOAN_SCALE;  
            
            //if the liquidation is the entire loan we need to record more
            if(totalUserCollateral == liquidationAmount){
                //and some of the loan is not being repaid.
                if(isoUSDBorrowed > isoUSDreturning){
                    //if a user is being fully liquidated we will forgive any remaining debt so it
                    // doesn't roll over if they open a new loan of the same collateral.
                    delete isoUSDLoanAndInterest[_collateralAddress][_loanHolder];
                    emit BadDebtCleared(_loanHolder, msg.sender, isoUSDBorrowed - isoUSDreturning, currencyKey);
                    
                }
            }
            //finally we call an internal function that updates mappings
            // burns the liquidator's isoUSD and transfers the collateral to the liquidator as payment
            _redeemLPTokens(_collateralAddress, liquidationAmount, _loanHolder);
            _liquidate(_loanHolder, _collateralAddress, liquidationAmount, isoUSDreturning, currencyKey, virtualPrice);
            
        } 
}