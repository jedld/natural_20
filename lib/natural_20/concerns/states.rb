module Natural20::States
  def new_state(entity)
    OpenStruct.new({
      entity: entity,
      children: [],
      states: {},
      callback: nil
    })
  end

  def transaction(&block)
    Thread.current[:transaction] ||= []
    Thread.current[:transaction].push([])
    block.call
    Thread.current[:transaction].pop
  end

  def txn(entity, method_name, params = [])
    raise "Invalid transaction state. no enclosing transaction block" unless Thread.current[:transaction]
    Thread.current[:transaction].last << Natural20::Transaction.new(entity, method_name, params).commit
  end
end