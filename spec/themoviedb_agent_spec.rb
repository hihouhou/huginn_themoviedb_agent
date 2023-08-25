require 'rails_helper'
require 'huginn_agent/spec_helper'

describe Agents::ThemoviedbAgent do
  before(:each) do
    @valid_options = Agents::ThemoviedbAgent.new.default_options
    @checker = Agents::ThemoviedbAgent.new(:name => "ThemoviedbAgent", :options => @valid_options)
    @checker.user = users(:bob)
    @checker.save!
  end

  pending "add specs here"
end
