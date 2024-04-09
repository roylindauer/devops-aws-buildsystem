def mock_env(partial_env_hash)
  old = ENV.to_hash
  ENV.clear
  ENV.update partial_env_hash
  begin
    yield
  ensure
    ENV.replace old
  end
end

