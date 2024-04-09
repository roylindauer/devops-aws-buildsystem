require 'json'
require 'minitest/autorun'

require_relative '../helpers'
require_relative '../../buildsystem'

class TestBuildSystem < Minitest::Test
    def test_is_ci
        mock_env({}) do
            refute BuildSystem.is_ci?
        end
        
        mock_env({'CI' => '1'}) do
            assert BuildSystem.is_ci?
        end
    end

    def test_convert_object_to_arg
        assert_equal '', BuildSystem.convert_object_to_arg(flag: '--env', args: {})
        assert_equal '--env foo=bar --env baz=qux', BuildSystem.convert_object_to_arg(flag: '--env', args: {foo: 'bar', baz: 'qux'})
    end

    def test_convert_object_to_args
        assert_nil BuildSystem.convert_object_to_args(nil)
        assert_equal ['foo=bar'], BuildSystem.convert_object_to_args({foo: 'bar'})
    end

    def test_default_task_environment
        mock_env({
            'ENC_KEY' => '1',
            'GITHUB_RUN_ID' => '1234',
            'GITHUB_REF_NAME' => 'production'
        }) do
            assert_equal([
                'ENV=PRODUCTION',
                'ENC_KEY=1',
                'BUILD_NUM=1234',
                'DEPLOY_ENV=PRODUCTION'
            ], BuildSystem.default_task_environment)
        end
    end
end
