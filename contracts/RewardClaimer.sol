// SPDX-License-Identifier: MIT
// RewardClaimer.sol for isomorph.loans
// Bug bounties available

pragma solidity =0.8.9; 
pragma abicoder v2;

//Interfaces
import "./interfaces/ICollateralBook.sol";

//Lyra Interfaces
import "./helper/interfaces/IMultiDistributor.sol";

//Open Zeppelin dependancies
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


/// Lyra LP Tokens are eligible for rewards, currently OP and stkLYRA, in order to ensure these are fairly allocated
/// to end users we generate a rewardClaimer contract per user for each collateral type they deposit. 
/// This contract then holds their collateral in place of the vault and so is eligible for the rewards distributed by Lyra. 
contract RewardClaimer {

    address loanHolder;
    address vaultLyra;
    IERC20 LPToken;
    ICollateralBook collateralBook;

    modifier onlyLoanHolder(){
        require(msg.sender == loanHolder, "Caller is not loan holder");
        _;
    }

    modifier onlyVaultLyra(){
        require(msg.sender == vaultLyra, "Caller is not Vault Lyra");
        _;
    }
   
   /// @dev On construction we set the two addresses which are allowed to interact with the contract
   /// these never change so a simple system is used.
   /// @param _loanHolder the address of the user depositing the Lyra LP token to Isomorph's Vault Lyra 
   /// @param _vaultLyra the address of the Vault Lyra where assets are received from and sent to.
   constructor(address _loanHolder, address _vaultLyra, address _LPToken, ICollateralBook _collateralBook){
    loanHolder = _loanHolder;
    vaultLyra = _vaultLyra;
    LPToken = IERC20(_LPToken);
    collateralBook = ICollateralBook(_collateralBook);
   }

    /// because the multidistributor address might possibly change we allow the user to specify it, 
    /// there is no harm in this as the RewardClaimer contract has no permissions elsewhere.
    function claimLyraRewards(address[] calldata _tokens, address distributor) onlyLoanHolder external{
        IMultiDistributor(distributor).claim(_tokens);
        uint256 length = _tokens.length;
        for(uint256 i =0; i < length; i++){
            require(!collateralBook.collateralValid(_tokens[i]), "Cannot withdraw collaterals");
            IERC20 currentToken = IERC20(_tokens[i]);
            uint256 amount = currentToken.balanceOf(address(this));
            currentToken.transfer(msg.sender, amount);        
        }
        
    }

    /// The vault calls this function to withdraw LPTokens that had been used as loan collateral
    /// @dev all LPTokens in the contract belong to the loanHolder and so no accounting is needed
    function withdraw(uint256 _amount) onlyVaultLyra external{
        LPToken.transfer(vaultLyra, _amount);
    }

}