require 'spec_helper'

module NetsuiteIntegration
  module Services
    describe CustomerRefund do
      include_examples "config hash"
      include_context "connect to netsuite"

      let(:customer_id)         { '75' }
      let(:payment_method_id)   { '1' }
      let(:deposits) { [double("CustomerDeposit", internal_id: '8079')] }
      let(:sales_order)        { double("SalesOrder", external_id: 'R123456789') }

      subject { described_class.new config, customer_id, payment_method_id }

      it "creates customer refund give sales order id" do
        VCR.use_cassette("customer_refund/create") do
          expect(subject.create sales_order, deposits).to be_true
        end
      end

      it "finds customer refund by external_id" do
        deposits = [double("CustomerDeposit", internal_id: "19492")]

        VCR.use_cassette("customer_refund/find_by_external_id") do
          expect(subject.find_by_external_id deposits).to be_a NetSuite::Records::CustomerRefund
        end
      end
    end
  end
end
