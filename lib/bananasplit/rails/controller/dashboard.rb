class BananaSplit
  module Rails
    module Controller
      module Dashboard

        def index
          @experiments = BananaSplit::Experiment.all
        end

      end
    end
  end
end
