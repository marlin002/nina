class DefinitionsController < ApplicationController
  def index
    @definitions = DefinitionsExtractorService.call
  end
end
