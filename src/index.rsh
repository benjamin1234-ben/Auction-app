'reach 0.1';

const AuctionProps = Object({
  startingBid: UInt,
  timeout: UInt,
  auctionItem: Bytes(128)
});

const BidderProps = {
  getBid: Fun([UInt], Maybe(UInt)),
  showAuctionProps: Fun([UInt, UInt, Bytes(128)], Null)
};

const OwnerInterface = {
  showOwner: Fun([Bytes(128), Address], Null),
  getAuctionProps: Fun([], AuctionProps),
  ...BidderProps 
};

const CreatorInterface = {
  ...OwnerInterface,
  getId: Fun([], Bytes(128))
};

const emptyAuction = { startingBid, timeout, auctionItem };

export const main = Reach.App(() => {

    const Creator = Participant('Creator', CreatorInterface);
    const Owner = ParticipantClass('Owner', OwnerInterface);
    init();

    Creator.only(() => {
      const id = declassify(interact.getId());
    });
    Creator.publish(id);

    var owner = Creator;
    invariant(balance() == 0);
    while (true) {
      commit();

      // Have the owner publish info about the auction
      Owner.only(() => {
        interact.showOwner(id, owner);
        const amOwner = this == owner;
        const { startingBid, timeout, auctionItem } = amOwner ? declassify(interact.getAuctionProps()) : emptyAuction;
        interact.showAuctionProps(startingBid, timeout, auctionItem);
      });
      Owner
        .publish(startingBid, timeout, auctionItem)
        .when(amOwner)
        .timeout(false);

      const [ timeRemaining, keepGoing ] = makeDeadline(timeout);

      // Let them fight for the best bid
      const [ winner, isFirstBid, currentPrice ] =
        parallelReduce([ owner, true, startingBid ])
          .invariant(balance() == (isFirstBid ? 0 : currentPrice))
          .while(keepGoing())
          .case(Owner,
            () => {
              const mbid = (this != owner && this != winner) ? declassify(interact.getBid(currentPrice)) : Maybe(UInt).None();
              return ({
                when: maybe(mbid, false, ((bid) => bid > currentPrice)),
                msg : fromSome(mbid, 0),
              });
            },
            (bid) => bid,
            (bid) => {
              require(bid > currentPrice);
              // Return funds to previous highest bidder
              transfer(isFirstBid ? 0 : currentPrice).to(winner);
              return [ this, false, bid ];
            }
          )
          .timeRemaining(timeRemaining());

      transfer(isFirstBid ? 0 : currentPrice).to(owner);

      owner = winner;
      continue;
    };

    commit();
    exit();

  });