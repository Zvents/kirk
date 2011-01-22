require 'spec_helper'

describe 'Kirk::Server' do
  it "runs the server" do
    start hello_world_path

    get '/'
    last_response.should be_successful
    last_response.should have_body('Hello World')
  end

  it "runs the server on the specified port" do
    path = hello_world_path

    start do
      rack "#{path}" do
        listen 9091
      end
    end

    host! 'localhost', 9091

    get '/'
    last_response.should be_successful
    last_response.should have_body('Hello World')
  end

  it "can start multiple applications" do
    path1 = hello_world_path
    path2 = goodbye_world_path

    start do
      rack "#{path1}" do
        listen '127.0.0.1:9090'
      end

      rack "#{path2}" do
        listen ':9090'
      end
    end

    get '/'
    last_response.should be_successful
    last_response.should have_body('Hello World')

    host! IP_ADDRESS, 9090

    get '/'
    last_response.should have_body('Goodbye World')
  end

  it "doesn't require 'bundler/setup' if there is no Gemfile" do
    start require_as_app_path

    get '/'
    last_response.should be_successful
    last_response.should have_body('ActiveSupport')
  end

  it "reloads the server" do
    start randomized_app_path

    get '/'
    num = last_response.body

    get '/'
    last_response.body.should == num

    touch randomized_app_path('REVISION')
    # Gives the server the time to see the
    # revision change and reload the app
    sleep 2

    get '/'
    last_response.body.should_not == num
  end
end
