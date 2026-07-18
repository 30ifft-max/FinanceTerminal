namespace :trade_log do
  desc "Backfill closed positions from existing trades (idempotent)"
  task backfill_closed_positions: :environment do
    pairs = Trade.joins(entry: :account)
      .where(accounts: { accountable_type: %w[Investment Crypto] })
      .where.not(qty: 0)
      .distinct
      .pluck("entries.account_id", :security_id)

    pairs.each do |account_id, security_id|
      ClosedPosition.rebuild_for!(Account.find(account_id), Security.find(security_id))
    end

    puts "Rebuilt closed positions for #{pairs.size} account/security pairs (#{ClosedPosition.count} records)."
  end
end
