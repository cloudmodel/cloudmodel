require 'spec_helper'

describe CloudModel::BaseWorker do
  context 'render' do
    it 'should call render on a new instance of ActionView::Base and pass return value' do
      action_view = double(ActionView::Base)
      ActionView::Base.stub(:new).and_return action_view
      action_view.should_receive(:view_paths=).with ActionController::Base.view_paths
      action_view.should_receive(:render).with(template: 'my_template', locals: {a:1, b:2}).and_return 'rendered template'
      expect(subject.render 'my_template', a: 1, b: 2).to eq 'rendered template'
    end
  end
end