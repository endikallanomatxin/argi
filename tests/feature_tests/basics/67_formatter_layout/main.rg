Point:Type=(
.x:Int32=1
.long_name:UInt8=2
)
identity#(.t:Type)(.value:t)->(.result:t):={ result=value }
main()->(.status_code:Int32=0):={
point:Point=Point(
.x=[2+3]*4,
.long_name=7,
)
if point.x!=20 or point.long_name!=7 {status_code=1}
copied:=identity#(.t:Int32)(.value=point.x)
if copied!=20 {status_code=2}
}
