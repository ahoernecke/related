module Related
  class Node < Entity
    module QueryMethods
      def relationships
        query = self.query
        query.result_type = :relationships
        query
      end

      def nodes
        query = self.query
        query.result_type = :nodes
        query
      end

      def outgoing(type)
        query = self.query
        query.relationship_type = type
        query.direction = :out
        query
      end

      def incoming(type)
        query = self.query
        query.relationship_type = type
        query.direction = :in
        query
      end

      def limit(count)
        query = self.query
        query.limit = count
        query
      end

      def depth(depth)
        query = self.query
        query.depth = depth
        query
      end

      def include_start_node
        query = self.query
        query.include_start_node = true
        query
      end

      def path_to(node)
        query = self.query
        query.destination = node
        query.search_algorithm = :depth_first
        query
      end

      def shortest_path_to(node)
        query = self.query
        query.destination = node
        query.search_algorithm = :dijkstra
        query
      end
    end

    include QueryMethods

    class Query
      include QueryMethods

      attr_reader :result

      attr_writer :result_type
      attr_writer :relationship_type
      attr_writer :direction
      attr_writer :limit
      attr_writer :depth
      attr_writer :include_start_node
      attr_writer :destination
      attr_writer :search_algorithm

      def initialize(node)
        @node = node
        @result_type = :nodes
        @depth = 4
      end

      def each(&block)
        self.to_a.each(&block)
      end

      def map(&block)
        self.to_a.map(&block)
      end

      def to_a
        perform_query unless @result
        if @result_type == :nodes
          Related::Node.find(@result)
        else
          Related::Relationship.find(@result)
        end
      end

      def count
        @count = Related.redis.scard(key)
        @limit && @count > @limit ? @limit : @count
      end

      def size
        @count || count
      end

      def include?(entity)
        if @destination
          self.to_a.include?(entity)
        else
          if entity.is_a?(Related::Node)
            @result_type = :nodes
            Related.redis.sismember(key, entity.to_s)
          elsif entity.is_a?(Related::Relationship)
            @result_type = :relationships
            Related.redis.sismember(key, entity.to_s)
          end
        end
      end

      def union(query)
        @result_type = :nodes
        @result = Related.redis.sunion(key, query.key)
        self
      end

      def diff(query)
        @result_type = :nodes
        @result = Related.redis.sdiff(key, query.key)
        self
      end

      def intersect(query)
        @result_type = :nodes
        @result = Related.redis.sinter(key, query.key)
        self
      end

    protected

      def key(node=nil)
        if @result_type == :nodes
          "#{node ? node.to_s : @node.to_s}:nodes:#{@relationship_type}:#{@direction}"
        else
          "#{node ? node.to_s : @node.to_s}:rel:#{@relationship_type}:#{@direction}"
        end
      end

      def query
        self
      end

      def perform_query
        @result = []
        if @destination
          @result_type = :nodes
          @result = self.send(@search_algorithm, [@node.id])
          @result.shift unless @include_start_node
          @result
        else
          if @limit
            @result = (1..@limit.to_i).map { Related.redis.srandmember(key) }
          else
            @result = Related.redis.smembers(key)
          end
        end
      end

      def depth_first(nodes, depth = 0)
        return [] if depth > @depth
        nodes.each do |node|
          if Related.redis.sismember(key(node), @destination.id)
            return [node, @destination.id]
          else
            res = depth_first(Related.redis.smembers(key(node)), depth+1)
            return [node] + res unless res.empty?
          end
        end
        return []
      end

      def dijkstra(nodes, depth = 0)
        return [] if depth > @depth
        shortest_path = []
        nodes.each do |node|
          if Related.redis.sismember(key(node), @destination.id)
            return [node, @destination.id]
          else
            res = dijkstra(Related.redis.smembers(key(node)), depth+1)
            if res.size > 0
              res = [node] + res
              if res.size < shortest_path.size || shortest_path.size == 0
                shortest_path = res
              end
            end
          end
        end
        return shortest_path
      end

    end

  protected

    def query
      Query.new(self)
    end

  end
end