require 'autoproj/test'

module Autoproj
    module PackageManagers
        describe BundlerManager do
            describe ".run_bundler" do
                it "defaults to the workspace's shim if program['bundler'] is not initialized" do
                    Autobuild.programs['bundle'] = nil
                    ws = flexmock(dot_autoproj_dir: '/some/path')
                    ws.should_receive(:run)
                      .with(any, any, '/some/path/bin/bundle', 'some', 'program', Hash, Proc)
                      .once
                    BundlerManager.run_bundler(ws, 'some', 'program',
                                               gem_home: '/gem/home',
                                               gemfile: '/gem/path/Gemfile')
                end
            end

            describe "#initialize_environment" do
                before do
                    @ws = ws_create
                    @bundler_manager = BundlerManager.new(@ws)
                end

                def run_bundler_config
                    `BUNDLE_GEMFILE=#{@ws.prefix_dir}/gems/Gemfile bundle config`.split("\n")
                end

                it "adds build configurations" do
                    BundlerManager.configure_build_for('testgem', '--some=config', ws: @ws)
                    @bundler_manager.initialize_environment

                    lines = run_bundler_config.each_cons(2).find do |a, b|
                        a =~ /build.testgem/
                    end
                    assert_match(/Set for your local app.*: "--some=config"/,
                                 lines[1])
                end
                it "updates existing build configurations" do
                    BundlerManager.configure_build_for('testgem', '--some=config', ws: @ws)
                    @bundler_manager.initialize_environment
                    BundlerManager.configure_build_for('testgem', '--some=other', ws: @ws)
                    @bundler_manager.initialize_environment

                    lines = run_bundler_config.each_cons(2).find do |a, b|
                        a =~ /build.testgem/
                    end
                    assert_match(/Set for your local app.*: "--some=other"/,
                                 lines[1])
                end
                it "removes obsolete build configurations" do
                    BundlerManager.configure_build_for('testgem', '--some=config', ws: @ws)
                    @bundler_manager.initialize_environment
                    BundlerManager.remove_build_configuration_for('testgem', ws: @ws)
                    @bundler_manager.initialize_environment

                    lines = run_bundler_config.each_cons(2).find do |a, b|
                        a =~ /build.testgem/
                    end
                    refute lines
                end
            end
        end
    end
end
