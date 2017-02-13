loadfile( 'courseplay/generateCourse.lua')

-- a point has the following attributes:
-- x
-- y
-- edge : vector from this point to the next
-- tangent : the tangent vector of the curve at this point,
--           calculated as the vector between the 
--           the previous and next points
-- directionStats : edge lengths per direction range, used
--                  to figure out the longest edge, or, the
--                  optimum direction of tracks
--                  The key in this table is a 20 degree wide range
--                  between -180 and +180, the value is the total
--                  length of edges pointing in that range

-- calculates the polar coordinates of x, y with some filtering
-- around pi/2 where tan is infinite
function toPolar( x, y )
  local length = math.sqrt( x * x + y * y )
  local bigEnough = 1000
  if ( x == 0 ) or ( math.abs( y/x ) > bigEnough ) then
    -- pi/2 or -pi/2
    if y >= 0 then 
      return math.pi / 2, length  -- north
    else 
      return - math.pi / 2, length -- south
    end 
  else
    return math.atan2( y, x ), length 
  end
end

--- Add a vector defined by polar coordinates to a point
-- @param x x coordinate of point
-- @param x y coordinate of point
-- @param angle angle of polar vector
-- @param length length of polar vector
-- @return x and y of the resulting point
function addPolarVectorToPoint( x, y, angle, length )
  return { x = x + length * math.cos( angle ),
           y = y + length * math.sin( angle )}
end
--- Get the average of two angles. 
-- Works fine even for the transition from -pi/2 to +pi/2
function getAverageAngle( a1, a2 )
  -- convert the 0 - -180 range into 180 - 360
  if math.abs( a1 - a2 ) > math.pi then
    if a1 < 0 then a1 = 2 * math.pi + a1 end
    if a2 < 0 then a2 = 2 * math.pi + a2 end
  end
  -- calculate average in this range
  local avg = ( a1 + a2 ) / 2
  -- convert back to 0 - -180 if necessary
  if avg > math.pi then avg = avg - 2 * math.pi end
  return avg
end

--- Get difference between two angles, even through 
-- -pi/2 and + pi/2
function getDeltaAngle( a1, a2 )
  -- convert the 0 - -180 range into 180 - 360
  if math.abs( a1 - a2 ) > math.pi then
    if a1 < 0 then a1 = 2 * math.pi + a1 end
    if a2 < 0 then a2 = 2 * math.pi + a2 end
  end
  -- calculate difference in this range
  return a2 - a1
end

--- This is kind of a low pass filter. If the 
-- direction change to the  next point is too big, 
-- the last point is removed
-- If the distance to the next point is less than distanceThreshold,
-- the current point is removed and the next one is replaced with a 
-- point between the current and the next.
function applyLowPassFilter( polygon, angleThreshold, distanceThreshold )
  local ix = function( a ) return getPolygonIndex( polygon, a ) end
  local index = 1
  repeat
    local cp, np = polygon[ ix( index )], polygon[ ix( index + 1 )]
    -- need to recalculate the edge length as we are moving points 
    -- around here
    local angle, length = toPolar( np.x - cp.x, np.y - cp.y )
    local isTooClose = length < distanceThreshold
    local isTooSharp = math.abs( getDeltaAngle( np.edge.angle, cp.edge.angle )) > angleThreshold 
    if isTooClose then
      -- replace current and next point with something in the middle
      polygon[ ix( index + 1 )].x, polygon[ ix( index + 1 )].y = _mid( cp, np )
    end
    if isTooSharp or isTooClose then
      table.remove( polygon, ix( index ))
      --table.insert( marks, cp )
    else
      index = index + 1
    end
  until index > #polygon
end

function calculatePolygonData( polygon )
  local ix = function( a ) return getPolygonIndex( polygon, a ) end
  local directionStats = {}
  for i, point in ipairs( polygon ) do
    local pp, cp, np = polygon[ ix( i - 1 )], polygon[ ix( i )], polygon[ ix( i + 1 )]
    local dx = np.x - pp.x 
    local dy = np.y - pp.y
    local angle, length = toPolar( dx, dy )
    -- vector from the previous to the next point
    polygon[ i ].tangent = { angle=angle, length=length, dx=dx, dy=dy }
    dx = cp.x - pp.x
    dy = cp.y - pp.y
    angle, length = toPolar( dx, dy )
    -- vector from the previous to this point
    polygon[ i ].edge = { angle=angle, length=length, dx=dx, dy=dy }
    addToDirectionStats( directionStats, angle, length )
  end
  polygon.directionStats = directionStats
  polygon.bestDirection = getBestDirection( directionStats )
end

function addToDirectionStats( directionStats, angle, length )
  local width = 10
  local range = math.floor( math.deg( angle ) / width ) * width + width / 2
  if directionStats[ range ] then  
    directionStats[ range ].length = directionStats[ range ].length + length
    table.insert( directionStats[ range ].dirs, math.deg( angle ))
  else
    directionStats[ range ] = { length=0, dirs={}}
  end
end

function getBestDirection( directionStats )
  local best = { range = 0, length = 0 }
  for range, stats in pairs( directionStats ) do
    if stats.length > best.length then 
      best.length = stats.length
      best.range = range
    end
  end
  local sum = 0
  for i, dir in ipairs( directionStats[ best.range ].dirs ) do
    sum = sum + dir
  end
  best.dir = math.floor( sum / #directionStats[ best.range ].dirs)
  return best
end

--- Removes loops at corners by looking at the last 
-- few sections. If the last section intersects one 
-- of the previous sections, there is a loop and we 
-- replace it with the intersection point.
function removeLoops( polygon, loopFilterLength )
  local result = {}
  local ix = function( a ) return getPolygonIndex( polygon, a ) end
  for i, point in ipairs( polygon ) do
    local lastSection = { x1 = polygon[ ix( i )].x,
                          y1 = polygon[ ix( i )].y,
                          x2 = polygon[ ix( i - 1 )].x,
                          y2 = polygon[ ix( i - 1 )].y }
    local intersectionAt = nil
    local xPoint = nil
    -- start with the section before the last ( -2 ) as 
    -- two connected section always intersect 
    for j = i - 2, i - loopFilterLength, -1 do
      -- iterate through the last loopFilterLength sections and see if 
      -- any of these intersect the current section
      if polygon[ ix( j )] and polygon[ ix( j - 1 )] then
        local currentSection = { x1 = polygon[ ix( j )].x,
                                 y1 = polygon[ ix( j )].y,
                                 x2 = polygon[ ix( j - 1 )].x,
                                 y2 = polygon[ ix( j - 1 )].y }
        xPoint = getIntersection( lastSection.x1, lastSection.y1, 
                                  lastSection.x2, lastSection.y2, 
                                  currentSection.x1, currentSection.y1,
                                  currentSection.x2, currentSection.y2 )
        if xPoint then 
          --print( "intersection between ", i, ix( i - 1 ), ix( i ), j, ix( j - 1 ), ix( j ) )
          intersectionAt = j
          break
        end
      end
    end
    if intersectionAt then
      -- replace that point with the intersection
      polygon[ intersectionAt ] = { x = xPoint.x, y = xPoint.y }
     -- table.insert( marks, polygon[ intersectionAt])
      -- and mark the rest up until and including the current for
      -- removal (don't remove here as we are iterating through the table
      for j = intersectionAt + 1, i do
        polygon[ ix( j )].remove = true
      end
    end
  end
  local i = 1
  repeat
    if ( polygon[ i ].remove ~= nil ) then 
      --table.insert( marks, polygon[ i ])
      table.remove( polygon, i )
    else
      i = i + 1
    end
  until i > #polygon
  calculatePolygonData( polygon )
end

--- Iterate through an elements of a polygon with 
-- an overlap, that is, more than a full circle
--
function polygonIterator( polygon, overlap )
  local i = 0
  local n = #polygon
  return function()
           i = i + 1
           if i > #polygon then i = 1 end
           if i <= #polygon + overlap then 
             return i, polygon[ i ] 
           end
         end
end

--- handle negative indices by circling back to 
-- the end of the polygon
function getPolygonIndex( polygon, index )
  if index > #polygon then
    return index - #polygon
  elseif index > 0 then
    return index
  elseif index == 0 then
    return #polygon
  else
    return #polygon + index 
  end
end

function getIntersection(A1x, A1y, A2x, A2y, B1x, B1y, B2x, B2y)
	local s1_x, s1_y, s2_x, s2_y ;
	s1_x = A2x - A1x;
	s1_y = A2y - A1y;
	s2_x = B2x - B1x;
	s2_y = B2y - B1y;

	local s, t;
	s = (-s1_y * (A1x - B1x) + s1_x * (A1y - B1y)) / (-s2_x * s1_y + s1_x * s2_y);
	t = ( s2_x * (A1y - B1y) - s2_y * (A1x - B1x)) / (-s2_x * s1_y + s1_x * s2_y);

	if (s >= 0 and s <= 1 and t >= 0 and t <= 1) then
		--Collision detected
		local x = A1x + (t * s1_x);
		local y = A1y + (t * s1_y);
		return { x = x, y = y };
	end;

	--No collision
	return nil;
end;

function createRectangularPolynom( x, y, dx, dy, step )
  local rect = {}
  for ix = x, x + dx, step do
    table.insert( rect, { x = ix, y = y })
    print( rect[ #rect ].x, rect[ #rect].y )
  end
  for iy = y + step, y + dy, step do
    table.insert( rect, { x = x + dx, y = iy })
    print( rect[ #rect ].x, rect[ #rect].y )
  end
  for ix = x + dx - step, x, -step do
    table.insert( rect, { x = ix, y = y + dy })
    print( rect[ #rect ].x, rect[ #rect].y )
  end
  for iy = y + dy - step, y, -step do
    table.insert( rect, { x = x, y = iy })
    print( rect[ #rect ].x, rect[ #rect].y )
  end
  return rect
end

function getBoundingBox( polygon )
  local minX, maxX, minY, maxY = 10000, -10000, 10000, -10000
  for i, point in ipairs( polygon ) do
    if ( point.x < minX ) then minX = point.x end
    if ( point.y < minY ) then minY = point.y end
    if ( point.x > maxX ) then maxX = point.x end
    if ( point.y > maxY ) then maxY = point.y end
  end
  return { minX=minX, maxX=maxX, minY=minY, maxY=maxY }
end 

