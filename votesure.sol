// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract InsurancePlatform {
    struct InsurancePlan {
        uint id;
        address insurer;
        string name;
        uint premium;
        uint payout;
        uint duration;
        string detailHash; // 保险详情的IPFS哈希
        uint256 createdAt;
        uint votesFor;
        uint votesAgainst;
        uint status; // 0=投票中, 1=通过, 2=未通过
    }

    struct InsurancePurchase {
        uint purchaseId;  // 添加一个唯一的购买ID
        uint insuranceId;
        address buyer;
        uint256 validTill;
        uint status; // 0=未申请索赔, 1=索赔投票中, 2=成功索赔, 3=到期
    }

    struct Claim {
        uint id;
        address claimant;
        uint purchaseId;  // 使用购买ID而非保险ID
        string claimDetailHash; // 索赔详情的IPFS哈希
        uint votesFor;
        uint votesAgainst;
        uint status; // 0=投票中, 1=通过, 2=未通过
        uint256 createdAt;
    }

    InsurancePlan[] public insurancePlans;
    InsurancePurchase[] public insurancePurchases; // 添加一个数组来存储所有保险购买
    Claim[] public claims;
    mapping(address => uint[]) public purchaseIdsByUser; // 映射用户到其购买ID数组
    mapping(address => uint) public balances; // 用户余额

    uint public fundPool=100; // 资金池
    address public owner;
    uint public voteDuration = 120 seconds; // 演示用

    mapping(address => mapping(uint => bool)) public hasVotedOnPlan; // Track if a user has voted on a plan
    mapping(uint => mapping(address => bool)) public hasVotedOnClaim; // Track if a user has voted on a claim


    constructor() {
        owner = msg.sender;
    }

    function mint(uint _amount) public {
        balances[msg.sender] += _amount;
    }

    function createInsurancePlan(string memory _name, uint _premium, uint _payout, uint _duration, string memory _detailHash) public {
        require(msg.sender == owner, "Only owner can create insurance plans.");
        insurancePlans.push(InsurancePlan({
            id: insurancePlans.length,
            insurer: msg.sender,
            name: _name,
            premium: _premium,
            payout: _payout,
            duration: _duration,
            detailHash: _detailHash,
            createdAt: block.timestamp,
            votesFor: 0,
            votesAgainst: 0,
            status: 0
        }));
    }

    function voteForInsurancePlan(uint _id) public {
        require(_id < insurancePlans.length, "Insurance plan does not exist");
        require(!hasVotedOnPlan[msg.sender][_id], "You have already voted on this plan");
        InsurancePlan storage plan = insurancePlans[_id];
        require(plan.status == 0, "Voting has already been finalized");
        require(block.timestamp <= plan.createdAt + voteDuration, "Voting period has ended");

        hasVotedOnPlan[msg.sender][_id] = true;
        plan.votesFor++;
    }

    function voteAgainstInsurancePlan(uint _id) public {
        require(_id < insurancePlans.length, "Insurance plan does not exist");
        require(!hasVotedOnPlan[msg.sender][_id], "You have already voted on this plan");
        InsurancePlan storage plan = insurancePlans[_id];
        require(plan.status == 0, "Voting has already been finalized");
        require(block.timestamp <= plan.createdAt + voteDuration, "Voting period has ended");

        hasVotedOnPlan[msg.sender][_id] = true;
        plan.votesAgainst++;
    }

    function updateAllPlanStatuses() public {
        for (uint i = 0; i < insurancePlans.length; i++) {
            updatePlanStatus(i);
        }
    }

    function updatePlanStatus(uint _id) public {
        InsurancePlan storage plan = insurancePlans[_id];
        if (block.timestamp > plan.createdAt + voteDuration && plan.status == 0) {
            if (plan.votesFor > plan.votesAgainst) {
                plan.status = 1; // Plan approved
            } else {
                plan.status = 2; // Plan rejected
            }
        }
    }


    function purchaseInsurance(uint _insuranceId) public {
        require(balances[msg.sender] >= insurancePlans[_insuranceId].premium, "Insufficient balance.");
        InsurancePlan storage plan = insurancePlans[_insuranceId];
        require(plan.status == 1, "Insurance plan is not active.");

        uint platformFee = (plan.premium * 20) / 100;
        uint fundContribution = plan.premium - platformFee;
        balances[msg.sender] -= plan.premium;
        balances[owner] += platformFee;
        fundPool += fundContribution;

        uint newPurchaseId = insurancePurchases.length; // 生成新的购买ID
        insurancePurchases.push(InsurancePurchase({
            purchaseId: newPurchaseId, // 使用新生成的购买ID
            insuranceId: _insuranceId,
            buyer: msg.sender,
            validTill: block.timestamp + plan.duration,
            status: 0
        }));

        purchaseIdsByUser[msg.sender].push(newPurchaseId); // 将新购买ID添加到用户的购买记录中
    }


function createClaim(uint _purchaseId, string memory _claimDetailHash) public {
    require(_purchaseId < insurancePurchases.length, "Purchase does not exist.");
    InsurancePurchase storage purchase = insurancePurchases[_purchaseId];
    require(msg.sender == purchase.buyer, "You are not the owner of this insurance.");
    require(block.timestamp <= purchase.validTill, "Your insurance has expired.");
    require(purchase.status == 0, "A claim has already been filed for this purchase.");

    purchase.status = 1; // 更新状态为索赔投票中
    claims.push(Claim({
        id: claims.length,
        claimant: msg.sender,
        purchaseId: _purchaseId, // 改为使用购买ID
        claimDetailHash: _claimDetailHash,
        votesFor: 0,
        votesAgainst: 0,
        status: 0,
        createdAt: block.timestamp
    }));
}


function isInsured(address _user, uint _purchaseId) internal view returns (bool) {
    if (_purchaseId < insurancePurchases.length) {
        InsurancePurchase storage purchase = insurancePurchases[_purchaseId];
        return (purchase.buyer == _user && block.timestamp <= purchase.validTill);
    }
    return false;
}



function voteForClaim(uint _claimId) public {
    Claim storage claim = claims[_claimId];
    require(isEligibleToVoteOnClaim(msg.sender), "Not eligible to vote");
    require(!hasVotedOnClaim[_claimId][msg.sender], "You have already voted on this claim");
    require(block.timestamp <= claim.createdAt + voteDuration, "Voting period has ended");
    require(claim.status == 0, "Voting has already been finalized");

    hasVotedOnClaim[_claimId][msg.sender] = true;
    claim.votesFor++;
}


function voteAgainstClaim(uint _claimId) public {
    Claim storage claim = claims[_claimId];
    require(isEligibleToVoteOnClaim(msg.sender), "Not eligible to vote");
    require(!hasVotedOnClaim[_claimId][msg.sender], "You have already voted on this claim");
    require(block.timestamp <= claim.createdAt + voteDuration, "Voting period has ended");
    require(claim.status == 0, "Voting has already been finalized");

    hasVotedOnClaim[_claimId][msg.sender] = true;
    claim.votesAgainst++;
}


function updateClaimStatus(uint _claimId) public {
    Claim storage claim = claims[_claimId];
    require(block.timestamp >= claim.createdAt + voteDuration, "Voting period has not ended yet");
    require(claim.status == 0, "Voting has already been finalized");

    if (claim.votesFor > claim.votesAgainst) {
        claim.status = 1; // Claim approved
        finalizeClaimPayout(_claimId);
    } else {
        claim.status = 2; // Claim rejected
        InsurancePurchase storage purchase = insurancePurchases[claim.purchaseId];
        purchase.status = 0;
    }
}


function finalizeClaimPayout(uint _claimId) internal {
    Claim storage claim = claims[_claimId];
    InsurancePurchase storage purchase = insurancePurchases[claim.purchaseId];
    if (purchase.status == 1) { // Ensure the purchase is still in the claiming process
        purchase.status = 2; // Claim successful
        fundPool -= insurancePlans[purchase.insuranceId].payout;
        balances[claim.claimant] += insurancePlans[purchase.insuranceId].payout;
    }
}


function checkInsuranceExpiry() public {
    for (uint i = 0; i < insurancePurchases.length; i++) {
        if (block.timestamp > insurancePurchases[i].validTill && insurancePurchases[i].status != 2 && insurancePurchases[i].status != 1) {
            insurancePurchases[i].status = 3; // Mark as expired
        }
    }
}


function isEligibleToVoteOnClaim(address _voter) internal view returns (bool) {
    for (uint i = 0; i < insurancePurchases.length; i++) {
        if (insurancePurchases[i].buyer == _voter && block.timestamp <= insurancePurchases[i].validTill && insurancePurchases[i].status != 2) {
            return true;
        }
    }
    return false;
}


}
