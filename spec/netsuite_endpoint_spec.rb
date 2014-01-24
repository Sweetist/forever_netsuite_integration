require 'spec_helper'

describe NetsuiteEndpoint do
  include_examples 'request parameters'

  let(:request) do
    {
      message: 'product:poll',
      message_id: 123,
      payload: {
        parameters: parameters
      }
    }
  end

  context "inventory stock service" do
    let(:request) do
      {
        message: 'stock:query',
        message_id: 123,
        payload: {
          sku: "1100",
          parameters: parameters
        }
      }
    end

    it "gets quantity available of an item" do
      VCR.use_cassette("inventory_item/find_by_item_id") do
        post '/inventory_stock', request.to_json, auth
        expect(last_response).to be_ok
      end
    end

    context "item not found" do
      before { request[:payload][:sku] = "Im not there" }

      it "still returns 200 but give no stock:actual message" do
        VCR.use_cassette("inventory_item/item_not_found_by_id") do
          post '/inventory_stock', request.to_json, auth
          expect(last_response).to be_ok
          expect(json_response["messages"]).to be_blank
        end
      end
    end
  end

  it "fetches a collection of netsuite items as products" do
    VCR.use_cassette("inventory_item/search") do
      post '/products', request.to_json, auth
      expect(last_response).to be_ok
    end
  end

  context 'Product returns an empty collection' do
    before { NetsuiteIntegration::Product.stub_chain(:new, collection: []) }

    it 'returns notification telling its ok' do
      post '/products', request.to_json, auth
      expect(last_response).to be_ok
    end
  end

  describe '/orders' do
    context 'when order is new' do
      let(:request) do
        payload = Factories.order_new_payload
        payload['order']['number'] = "RERGERG4454354354"

        {
          message: 'order:new',
          message_id: 123,
          payload: payload.merge(parameters: parameters)
        }
      end

      it 'imports the order and returns an info notification' do
        VCR.use_cassette('order/import_service') do
          post '/orders', request.to_json, auth
        end

        expect(json_response['notifications'][0]['subject']).to match('imported into NetSuite')
      end
    end

    context 'when order has already been imported' do
      let(:request) do
        {
          message: 'order:new',
          message_id: 123,
          payload: Factories.order_updated_payload.merge(parameters: parameters)
        }
      end

      it 'creates customer deposit if order just got paid' do
        VCR.use_cassette('order/customer_deposit_on_updated_message') do
          post '/orders', request.to_json, auth
        end

        expect(json_response['notifications'][0]['subject']).to match('Customer Deposit created for NetSuite Sales Order')
      end

      context "was already paid" do
        let(:request) do
          {
            message: 'order:updated',
            message_id: 123,
            payload: Factories.order_new_payload.merge(parameters: parameters)
          }
        end

        it "just returns 200" do
          VCR.use_cassette('order/already_imported') do
            post '/orders', request.to_json, auth
          end

          expect(last_response.status).to eq 200
          expect(last_response.headers["Content-Type"]).to match "application/json"
        end
      end
    end

    context 'when order is canceled' do
      include_examples "config hash"
      include_context "connect to netsuite" 

      let(:customer_deposit) {
        VCR.use_cassette("customer_deposit/find_by_external_id") do
          NetsuiteIntegration::Services::CustomerDeposit.new(config).find_by_external_id('R123456789')
        end
      }

      let(:sales_order) {
        VCR.use_cassette("order/find_by_external_id") do
          NetsuiteIntegration::Services::CustomerDeposit.new(config).find_by_external_id('R123456789')
        end
      }    

      let(:request) do
        payload = Factories.order_canceled_payload

        {
          message: 'order:canceled',
          message_id: 123,
          payload: payload.merge(parameters: parameters)
        }
      end

      it 'issues customer refund and closes the order' do
        NetsuiteIntegration::Refund.any_instance.stub_chain(:customer_deposit_service, :find_by_external_id).and_return(customer_deposit)        
        NetsuiteIntegration::Refund.any_instance.stub_chain(:sales_order_service, :find_by_external_id).and_return(sales_order)
        NetsuiteIntegration::Refund.any_instance.stub_chain(:sales_order_service, :close!).and_return(true)

        VCR.use_cassette('customer_refund/create') do
          post '/orders', request.to_json, auth
        end

        expect(json_response['notifications'][0]['subject']).to match('Customer Refund created and NetSuite Sales Order')
      end          
    end
  end
end
