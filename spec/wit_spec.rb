require 'wit'
RSpec.describe Wit do
  context "req" do
    let(:wit) { Wit.new(timeout: 3, access_token: 'some_token') }

    it "raises Net::ReadTimeout exception" do
      stub_request(:any, /https:\/\/api\.wit\.ai*+/)
      .to_timeout

      expect do
        wit.message("some text message")
      end.to raise_error(Net::OpenTimeout)
    end

    it "returns expected json" do
      stub_request(:any, /https:\/\/api\.wit\.ai*+/)
      .to_return(status: 200, body: {}.to_s, headers: {})

      expect(wit.message("some text message")).to eq({})
    end
  end
end
