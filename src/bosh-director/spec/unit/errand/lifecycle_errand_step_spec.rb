require 'spec_helper'

module Bosh::Director
  describe Errand::LifecycleErrandStep do
    subject(:errand_step) do
      Errand::LifecycleErrandStep.new(
        runner,
        deployment_planner,
        errand_name,
        instance,
        instance_group,
        skip_errand,
        keep_alive,
        deployment_name,
        logger
      )
    end

    let(:deployment_planner) { instance_double(DeploymentPlan::Planner, template_blob_cache: template_blob_cache) }
    let(:runner) { instance_double(Errand::Runner) }
    let(:instance_group) { instance_double(DeploymentPlan::InstanceGroup, is_errand?: true) }
    let(:errand_name) { 'errand_name' }
    let(:skip_errand) { false }
    let(:template_blob_cache) { instance_double(Core::Templates::TemplateBlobCache) }
    let(:deployment_name) { 'deployment-name' }
    let(:errand_result) { Errand::Result.new(errand_name, exit_code, nil, nil, nil) }
    let(:instance) { instance_double(DeploymentPlan::Instance) }
    let(:keep_alive) { 'maybe' }
    let(:instance_group_manager) { instance_double(Errand::InstanceGroupManager) }
    let(:errand_instance_updater) { instance_double(Errand::ErrandInstanceUpdater) }

    before do
      allow(Errand::InstanceGroupManager).to receive(:new)
                                               .with(deployment_planner, instance_group, logger)
                                               .and_return(instance_group_manager)
      allow(Errand::ErrandInstanceUpdater).to receive(:new)
                                                .with(instance_group_manager, logger, errand_name, deployment_name)
                                                .and_return(errand_instance_updater)
    end

    describe '#prepare' do
      context 'when keep alive is true' do
        let(:keep_alive) { true }
        it 'updates instances with keep alive' do
          expect(errand_instance_updater).to receive(:create_vms).with(keep_alive)
          errand_step.prepare
        end
      end

      context 'when keep alive is false' do
        let(:keep_alive) { false }
        it 'updates instances without keep alive' do
          expect(errand_instance_updater).to receive(:create_vms).with(keep_alive)
          errand_step.prepare
        end
      end

      context 'when creating instances fails' do
        it 'should raise' do
          expect(errand_instance_updater).to receive(:create_vms).and_raise("OMG")
          expect { errand_step.prepare }.to raise_error("OMG")
        end
      end

      context 'when there are no changes' do
        let(:skip_errand) { true }
        it 'should not update the instances' do
          expect(errand_instance_updater).not_to receive(:create_vms)
          errand_step.prepare
        end
      end
    end

    describe '#run' do
      context 'when skip errand is true' do
        let(:skip_errand) { true }

        it 'logs and returns early' do
          expect(logger).to receive(:info).with('Skip running errand because since last errand run was successful and there have been no changes to job configuration')
          expect(errand_instance_updater).not_to receive(:with_updated_instances)
          errand_step.run(&lambda {})
        end

        it 'returns an empty result' do
          errand_step_run = errand_step.run(&lambda {})
          expect(errand_step_run.short_description).to eq("Errand 'errand_name' did not run (no configuration changes)")
          expect(errand_step_run.exit_code).to eq(-1)
        end
      end

      context 'when instance group is lifecycle errand' do
        let(:exit_code) { 0 }

        it 'runs the errand' do
          allow(instance).to receive(:to_s).and_return('instance-name')
          expect(template_blob_cache).to receive(:clean_cache!)
          expect(errand_instance_updater).to receive(:with_updated_instances).with(keep_alive) do |&blk|
            blk.call
          end

          block_evidence = false
          the_block = lambda {
            block_evidence = true
          }

          expect(runner).to receive(:run).with(instance) do |&blk|
            blk.call
          end.and_return(errand_result)

          result = errand_step.run(&the_block)

          expect(block_evidence).to be(true)
          expect(result.short_description).to eq("Errand 'errand_name' completed successfully (exit code 0)")
          expect(result.exit_code).to eq(0)
        end
      end

      context 'when something goes wrong' do
        it 'cleans the cache' do
          expect(template_blob_cache).to receive(:clean_cache!)
          expect(errand_instance_updater).to receive(:with_updated_instances).and_raise('omg')
          expect { errand_step.run(&lambda{}) }.to raise_error 'omg'
        end
      end
    end
  end
end
