/* Copyright (C) 2017 GovBlocks.io

  This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

  This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
    along with this program.  If not, see http://www.gnu.org/licenses/ */

pragma solidity 0.4.24;

import "./imports/openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./GBTStandardToken.sol";
import "./Upgradeable.sol";
import "./Governance.sol";
import "./GovernanceData.sol";
import "./ProposalCategory.sol";
import "./VotingType.sol";


contract Pool is Upgradeable {
    using SafeMath for uint;

    GBTStandardToken internal gbt;
    GBTStandardToken internal dAppToken;
    Governance internal gov;
    GovernanceData internal governanceDat;
    ProposalCategory internal proposalCategory;

    function () public payable {} //solhint-disable-line

    modifier onlySV {
        require(
            master.getLatestAddress("SV") == msg.sender 
            || master.isInternal(msg.sender) 
        );
        _;
    }

    /// @dev just to adhere to the interface
    function updateDependencyAddresses() public {
        gbt = GBTStandardToken(master.getLatestAddress("GS"));
        gov = Governance(master.getLatestAddress("GV"));
        governanceDat = GovernanceData(master.getLatestAddress("GD"));
        proposalCategory = ProposalCategory(master.getLatestAddress("PC"));
        dAppToken = GBTStandardToken(master.dAppToken());
    }

    /// @dev transfers its assets to latest addresses
    function transferAssets() public {
        address newPool = master.getLatestAddress("PL");
        if (address(this) != newPool) {
            uint gbtBal = gbt.balanceOf(address(this));
            uint ethBal = address(this).balance;
            if (gbtBal > 0)
                gbt.transfer(newPool, gbtBal);
            if (ethBal > 0)
                newPool.transfer(ethBal);
        }
    }

    /// @dev converts pool ETH to GBT
    /// @param _gbt number of GBT to buy multiplied 10^decimals
    function buyPoolGBT(uint _gbt) public onlySV {
        uint _wei = SafeMath.mul(_gbt, gbt.tokenPrice());
        _wei = SafeMath.div(_wei, uint256(10) ** gbt.decimals());
        gbt.buyToken.value(_wei)();
    }

    /// @dev user can calim the tokens rewarded them till now
    function claimReward(address _claimer) public {
        uint pendingGBTReward;
        uint pendingDAppReward;
        (pendingGBTReward, pendingDAppReward) = gov.calculateMemberReward(_claimer);
        if (pendingGBTReward != 0) {
            gbt.transfer(_claimer, pendingGBTReward);
        }
        if (pendingDAppReward != 0) {
            dAppToken.transfer(_claimer, pendingDAppReward);
        }
    }

    function getPendingReward(address _memberAddress) 
        public view returns (uint pendingGBTReward, uint pendingDAppReward) 
    {
        uint tempGBTReward;
        uint tempDAppRward;
        uint lastRewardProposalId = governanceDat.lastRewardDetails(_memberAddress);
        (pendingGBTReward, pendingDAppReward) = getPendingProposalReward(_memberAddress, lastRewardProposalId); 
        (tempGBTReward, tempDAppRward) = getPendingSolutionReward(_memberAddress, lastRewardProposalId);
        pendingGBTReward += tempGBTReward;
        pendingDAppReward += tempDAppRward;

        uint votingTypes = governanceDat.getVotingTypeLength();
        for (uint i = 0; i < votingTypes; i++) {
            VotingType votingType = VotingType(governanceDat.getVotingTypeAddress(i));
            (tempGBTReward, tempDAppRward) = votingType.getPendingReward(_memberAddress);
            pendingGBTReward += tempGBTReward;
            pendingDAppReward += tempDAppRward;
        }
    }

    function getPendingProposalReward(address _memberAddress, uint _lastRewardProposalId)
        public
        view
        returns (uint pendingGBTReward, uint pendingDAppReward)
    {
        uint allProposalLength = governanceDat.getProposalLength();
        uint finalVredict;
        uint8 proposalStatus;
        uint calcReward;
        uint subCat;
        bool rewardClaimed;
        for (uint i = _lastRewardProposalId; i < allProposalLength; i++) {
            if (_memberAddress == governanceDat.getProposalOwner(i)) {
                (rewardClaimed, subCat, proposalStatus, finalVredict) = 
                    governanceDat.getProposalDetailsById3(i, _memberAddress);
                if (
                    proposalStatus > 2 && 
                    finalVredict > 0 && 
                    governanceDat.getProposalIncentive(i) != 0 &&
                    !rewardClaimed
                ) {
                    calcReward = (proposalCategory.getRewardPercProposal(subCat).mul(governanceDat.getProposalIncentive(i))).div(100);  //solhint-disable-line
                    if (proposalCategory.isSubCategoryExternal(subCat))    
                        pendingGBTReward += calcReward;
                    else
                        pendingDAppReward += calcReward;                
                }
            }
        }
    }

    function getPendingSolutionReward(address _memberAddress, uint _lastRewardSolutionProposalId)
        public
        view
        returns (uint pendingGBTReward, uint pendingDAppReward)
    {
        uint allProposalLength = governanceDat.getProposalLength();
        uint calcReward;
        uint i;
        uint finalVerdict;
        uint solutionId;
        uint proposalId;
        uint totalReward;
        uint subCategory;

        for (i = _lastRewardSolutionProposalId; i < allProposalLength; i++) {
            (proposalId, solutionId, , finalVerdict, totalReward, subCategory) = 
                gov.getSolutionIdAgainstAddressProposal(_memberAddress, i);
            if (finalVerdict > 0 && finalVerdict == solutionId && proposalId == i 
                && !governanceDat.getRewardClaimed(i, _memberAddress)
            ) {
                calcReward = (proposalCategory.getRewardPercSolution(subCategory) * totalReward) / 100;
                if (proposalCategory.isSubCategoryExternal(subCategory))    
                    pendingGBTReward += calcReward;
                else
                    pendingDAppReward += calcReward;                
            }
        }
    }

    /// @dev Transfer Ether to someone    
    /// @param _amount Amount to be transferred back
    /// @param _receiverAddress address where ether has to be sent
    function transferEther(address _receiverAddress, uint256 _amount) public onlySV {
        _receiverAddress.transfer(_amount);
    }

    /// @dev Transfer token to someone    
    /// @param _amount Amount to be transferred back
    /// @param _receiverAddress address where tokens have to be sent
    /// @param _token address of token to transfer
    function transferToken(address _token, address _receiverAddress, uint256 _amount) public onlySV {
        GBTStandardToken token = GBTStandardToken(_token);
        token.transfer(_receiverAddress, _amount);
    }

}