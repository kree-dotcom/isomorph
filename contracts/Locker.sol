pragma solidity =0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./ConfirmedOwnerWithProposal.sol";

import "./interfaces/IVoter.sol";
import "./interfaces/IVotingEscrow.sol";
import "./interfaces/IRewardsDistributor.sol";

//ConfirmedOwnerWithProposal is an upgraded form of Ownable created by Chainlink with 2 stage proposal/acceptance for ownership
contract Locker is ConfirmedOwnerWithProposal(msg.sender, address(0)) {

    using SafeERC20 for IERC20;

    // VELO governance token
    IERC20 immutable public velo; 
    // Velodrome voter contract 
    IVoter immutable public voter;
    // Velodrome veVELO NFT contract, used to create voting locks
    IVotingEscrow immutable public votingEscrow;
    //Velodrome rewards distributor, used to claim VELO rebases for locked VELO tokens
    IRewardsDistributor immutable public rewardsDistributor;

    //array storing the Ids of each veNFT generated by lockVELO()
    uint256[] public veNFTIds;

    event RemoveExcessTokens(address token, address to, uint256 amount);
    event GenerateVeNFT(uint256 id, uint256 lockedAmount, uint256 lockDuration);
    event RelockVeNFT(uint256 id, uint256 lockDuration);
    event NFTVoted(uint256 id, uint256 timestamp);
    event WithdrawVeNFT(uint256 id, uint256 timestamp);
    event ClaimedBribes(uint256 id, uint256 timestamp);
    event ClaimedFees(uint256 id, uint256 timestamp);
    event ClaimedRebases(uint256[] id, uint256 timestamp);


    

    constructor(address _VeloAddress, 
                address _VoterAddress, 
                address _VotingEscrowAddress, 
                address _RewardsDistributorAddress){

        velo = IERC20(_VeloAddress);
        voter = IVoter(_VoterAddress);
        votingEscrow = IVotingEscrow(_VotingEscrowAddress);
        rewardsDistributor = IRewardsDistributor(_RewardsDistributorAddress);
    }

    /////// External functions callable by only the owner ///////

    /**
    *    @notice Function to lock the contracts VELO tokens as a veNFT for voting with
    *    @param _tokenAmount amount of VELO to lock into veNFT
    *    @param _lockDuration time in seconds you wish to lock the tokens for, 
    *           must be less than or equal to 4 years (4*365*24*60*60 = 126144000)
    **/
    function lockVELO(uint256 _tokenAmount, uint256 _lockDuration) external onlyOwner {
        //approve transfer of VELO to votingEscrow contract, bad pattern, prefer increaseApproval but VotingEscrow is not upgradable so should be ok
        //VELO.approve returns true always so it is of no use.
        //slither-disable-next-line unused-return
        velo.approve(address(votingEscrow), _tokenAmount);
        //create lock
        uint256 NFTId = votingEscrow.create_lock(_tokenAmount, _lockDuration);
        //store new NFTId for reference
        veNFTIds.push(NFTId);
        emit GenerateVeNFT(NFTId, _tokenAmount, _lockDuration);

    }
    
    /**
    *    @notice Function to relock existing veNFTs to get the maximum amount of voting power
    *    @param _NFTId Id of the veNFT you wish to relock
    *    @param _lockDuration time in seconds you wish to lock the tokens for, 
    *           must exceed current lock and must be less than or equal to 4 years (4*365*24*60*60 = 126144000)
    **/
    function relockVELO(uint256 _NFTId, uint256 _lockDuration) external onlyOwner{
        votingEscrow.increase_unlock_time(_NFTId, _lockDuration);
        emit RelockVeNFT(_NFTId, _lockDuration);
    }

    /**
    *    @notice Function to vote for pool gauge using one or more veNFTs
    *    @param _NFTIds array of Ids of the veNFTs you wish to vote with
    *    @param _poolVote the array of pools you wish to vote for, with weight stored in the respective slot of the _weights array
    *    @param _weights the array of pool weights relating to the pool addresses passed in, max value 10000 is 100%
    **/
    function vote(uint[] calldata _NFTIds, address[] calldata _poolVote, uint256[] calldata _weights) external onlyOwner {
        uint256 length = _NFTIds.length;
        for(uint256 i = 0; i < length; ++i ){
            voter.vote(_NFTIds[i], _poolVote, _weights);
            emit NFTVoted(_NFTIds[i], block.timestamp);
        }
        
    }

    /**
    *    @notice Function to withdraw veNFT's VELO tokens after lock has expired.
    *    @dev we delete the array entry related to this veNFT but leave it as 0 rather than resorting 
    *         this is a degisn decision as we are unlikely to call withdrawNFT for a long while (1+ years)
    *    @param _tokenId the Id of the veNFT you wish to burn and redeem the VELO associated with
    *    @param _index the slot of the array where this veNFT's id is stored.
    **/
    function withdrawNFT(uint256 _tokenId, uint256 _index) external onlyOwner {
        //ensure we are deleting the right veNFTId slot
        require(veNFTIds[_index] == _tokenId , "Wrong index slot");
        //abstain from current epoch vote to reset voted to false, allowing withdrawal
        voter.reset(_tokenId);
        //request withdrawal
        votingEscrow.withdraw(_tokenId);
        //delete stale veNFTId as veNFT is now burned.
        delete veNFTIds[_index];
        emit WithdrawVeNFT(_tokenId, block.timestamp);
    }
   
    /**
    *    @notice Function to withdraw VELO tokens or bribe rewards from contract by owner.
    *    @param _tokens array of addresses of ERC20 token you wish to receive
    *    @param _amounts array of amounts of ERC20 token you wish to withdraw, relating to the same slot of the _tokens array.
    **/
    function removeERC20Tokens(address[] calldata _tokens, uint256[] calldata _amounts) external onlyOwner {
        uint256 length = _tokens.length;
        require(length == _amounts.length, "Mismatched arrays");

        for (uint256 i = 0; i < length; ++i){
            IERC20(_tokens[i]).safeTransfer(msg.sender, _amounts[i]);
            emit RemoveExcessTokens(_tokens[i], msg.sender, _amounts[i]);
        }
        
    }

    /**
    *    @notice Function to transfer veNFT to another account
    *    @dev Because veNFTs can be transferred if the protocol should ever wish to sell 
              some veNFTs this enables them to do so before the 4 year lock expires.
    *    @param _tokenIds The array of ids of the veNFT tokens that we are transfering 
    **/
    function transferNFTs(uint256[] calldata _tokenIds, uint256[] calldata _indexes ) external onlyOwner {
        uint256 length = _tokenIds.length;
        require(length == _indexes.length, "Mismatched arrays");

        for (uint256 i =0; i < length; ++i){
            require(veNFTIds[_indexes[i]] == _tokenIds[i] , "Wrong index slot");
            delete veNFTIds[_indexes[i]];
            //abstain from current epoch vote to reset voted to false, allowing transfer
            voter.reset(_tokenIds[i]);
            //here msg.sender is always owner.
            votingEscrow.safeTransferFrom(address(this), msg.sender, _tokenIds[i]);
            //no event needed as votingEscrow emits one on transfer anyway
        }
    }

    /////// External functions callable by anyone ///////

    /**
    *    @notice Function to claim bribes associated to pools previously voted for
    *    @dev Anyone can call this function to reduce pressure on Multisig owner to sign every week
    *    @param _bribes array of addresses for the wrapped external bribe contract of each bribe
    *    @param _tokens array of token addresses we are claiming bribes in, i.e. the tokens we wish to receive
    *    @param _tokenIds The array of ids of the veNFT tokens that we are claiming for 
    **/
    function claimBribesMultiNFTs(address[] calldata _bribes, address[][] calldata _tokens, uint[] calldata _tokenIds) external {
        uint256 length = _tokenIds.length;
        for (uint256 i =0; i < length; ++i){
            voter.claimBribes(_bribes, _tokens, _tokenIds[i]);
            emit ClaimedBribes(_tokenIds[i], block.timestamp);
        }
    }

    /**
    *    @notice Function to claim fees associated to a pool previously voted for
    *    @dev Anyone can call this function to reduce pressure on Multisig owner to sign every week
    *    @dev internally claimFees and claimBribes are identical functions in Velodrome's voter contract, this is here for readability
    *    @param _fees array of addresses for the internal bribe contract of each fee pool
    *    @param _tokens array of token addresses we are claiming fees in, i.e. the tokens we wish to receive
    *    @param _tokenIds The array of ids of the veNFT tokens that we are claiming for 
    **/
    function claimFeesMultiNFTs(address[] calldata _fees, address[][] calldata _tokens, uint[] calldata _tokenIds) external {
        uint256 length = _tokenIds.length;
        for (uint256 i =0; i < length; ++i){
            voter.claimFees(_fees, _tokens, _tokenIds[i]);
            emit ClaimedFees(_tokenIds[i], block.timestamp);
        }
    }

    /**
    *    @notice Function to claim VELO rebase associated to NFTs previously voted with
    *    @dev Anyone can call this function to reduce pressure on Multisig owner to sign every week
    *    @param _tokenIds The array of ids of the veNFT tokens that we are claiming for 
    **/
    function claimRebaseMultiNFTs(uint256[] calldata _tokenIds) external {
        //claim_many always returns true unless a tokenId = 0 so return bool is not needed
        //slither-disable-next-line unused-return
       rewardsDistributor.claim_many(_tokenIds);
       emit ClaimedRebases(_tokenIds, block.timestamp);
    }

  
}
