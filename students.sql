--query to set the register limit from grade distribution. already done
-- with t as
-- (select course_offering_uuid, section_number, (COALESCE(gd.a_count,0) + COALESCE(gd.ab_count,0) + COALESCE(gd.b_count,0) + COALESCE(gd.bc_count,0) + COALESCE(gd.c_count,0) + COALESCE(gd.d_count,0) + COALESCE(gd.f_count,0) + COALESCE(gd.s_count,0) + COALESCE(gd.u_count,0) + COALESCE(gd.cr_count,0) + COALESCE(gd.n_count,0) + COALESCE(gd.p_count,0) + COALESCE(gd.i_count,0) + COALESCE(gd.nw_count,0) + COALESCE(gd.nr_count,0) + COALESCE(gd.other_count)) as lim from grade_distributions as gd)
--  update sections set reg_limit= lim  from t where sections.course_offering_uuid=t.course_offering_uuid and sections.num=t.section_number;

CREATE MATERIALIZED VIEW instructor_course AS
SELECT i.id as instructor_id,
		i.name as instructor_name,
		c.name as course_name,
		c.uuid as course_uuid,
		co.uuid as course_offering_uuid,
		co.term_code as course_offering_term,
		s.num as section_number
FROM ((((instructors i
	join teachings t on (i.id=t.instructor_id))
	join sections s on (t.section_uuid=s.uuid))
	join course_offerings co on (s.course_offering_uuid=co.uuid))
	join courses c on (co.course_uuid=c.uuid));

CREATE MATERIALIZED VIEW schedule_room AS
(
	select * from
	(
		SELECT distinct course_offering_uuid,
		sections.num as section_number,
		facility_code,room_code,--room data
		start_time,end_time,mon,tues,wed,thurs,fri,sat,sun --schedule data
		FROM sections, schedules, rooms
		where
		-- join constraints on rooms
		sections.room_uuid=rooms.uuid and sections.room_uuid is not NULL
		--join constraints on schedule
		and sections.schedule_uuid=schedules.uuid
	) as t1
	union
	(
		SELECT distinct course_offering_uuid,
		sections.num as section_number,
		NULL as facility_code, null as room_code,--room data
		start_time,end_time,mon,tues,wed,thurs,fri,sat,sun --schedule data
		FROM sections, schedules
		where
		-- join constraints on room
		 sections.room_uuid is NULL
		--join constraints on schedule
		and sections.schedule_uuid=schedules.uuid
	)
);
/*-----------------------------------------------------------------------------*/

--show the grade distribution percentage wise
create MATERIALIZED view grade_distribution_percentages AS
(
	SELECT t.course_offering_uuid, t.section_number,
	(cast (a_count as float)/t.total*100)::numeric(10,2) as a_count_p,
	(cast (ab_count as float)/t.total*100)::numeric(10,2) as ab_count_p,
	(cast (b_count as float)/t.total*100)::numeric(10,2) as b_count_p,
	(cast (bc_count as float)/t.total*100)::numeric(10,2) as bc_count_p,
	(cast (c_count as float)/t.total*100)::numeric(10,2) as c_count_p,
	(cast (d_count as float)/t.total*100)::numeric(10,2) as d_count_p,
	(cast (f_count as float)/t.total*100)::numeric(10,2) as f_count_p,
	(cast (s_count as float)/t.total*100)::numeric(10,2) as s_count_p,
	(cast (u_count as float)/t.total*100)::numeric(10,2) as u_count_p,
	(cast (cr_count as float)/t.total*100)::numeric(10,2) as cr_count_p,
	(cast (n_count as float)/t.total*100)::numeric(10,2) as n_count_p,
	(cast (p_count as float)/t.total*100)::numeric(10,2) as p_count_p,
	(cast (i_count as float)/t.total*100)::numeric(10,2) as i_count_p,
	(cast (nw_count as float)/t.total*100)::numeric(10,2) as nw_count_p,
	(cast (nr_count as float)/t.total*100)::numeric(10,2) as nr_count_p,
	(cast (other_count as float)/t.total*100)::numeric(10,2) as other_count_p
  from
	(
		SELECT course_offering_uuid,section_number, cast
		(
			(COALESCE(gd.a_count,0) + COALESCE(gd.ab_count,0) + COALESCE(gd.b_count,0) + COALESCE(gd.bc_count,0) + COALESCE(gd.c_count,0) + COALESCE(gd.d_count,0) + COALESCE(gd.f_count,0) + COALESCE(gd.s_count,0) + COALESCE(gd.u_count,0) + COALESCE(gd.cr_count,0) + COALESCE(gd.n_count,0) + COALESCE(gd.p_count,0) + COALESCE(gd.i_count,0) + COALESCE(gd.nw_count,0) + COALESCE(gd.nr_count,0) + COALESCE(gd.other_count)) as float
		) as total from grade_distributions as gd
	)
	as t, grade_distributions where t.course_offering_uuid=grade_distributions.course_offering_uuid and t.section_number=grade_distributions.section_number and t.total!=0
);
/*-----------------------------------------------------------------------------*/

--1-SearchCourse--
create or replace function search_course(
	CNAME text, 			--course id
	TC int 				--term_code
	)
returns table (
	course_offering_uuid text,
	section_number int,
	course_name text,
	course_limit int,
	instructors text,
	department_data text,
	facility_code text,
	room_code text,
	start_time int ,
	end_time int ,
	mon boolean ,
	tues boolean ,
	wed boolean ,
	thurs boolean ,
	fri boolean ,
	sat boolean ,
	sun boolean )
	as $$
DECLARE
	CNAME text :='%' || CNAME || '%' ;
begin
	return query

	(
		SELECT course_offering_uuid, t1.section_number, course_name, reg_limit as course_limit, instructors,
		concat_ws('-',subjects.code,subjects.abbreviation) as department_data,
		facility_code,room_code,--room data
		start_time,end_time,mon,tues,wed,thurs,fri,sat,sun --schedule data
		from
	 	(
	 		SELECT string_agg(instructor_course.instructor_name::text, ',') as instructors, course_name, course_offering_uuid, section_number 
	 		from instructor_course where instructor_course.course_name ilike CNAME and instructor_course.course_offering_term=TC
	 		GROUP by course_name, course_offering_uuid, section_number

	 	) as t1,
	 	sections, subject_memberships, schedule_room
	 	--join constraints on sections
	 	where t1.section_number=sections.num and t1.course_offering_uuid=sections.course_offering_uuid
	 	--join constraints on subject_memberships
	 	and t1.course_offering_uuid=subject_memberships.course_offering_uuid
	 	--join constraints on schedule_room
	 	and sections.course_offering_uuid=schedule_room.course_offering_uuid and sections.num=schedule_room.section_number
	) ;
end $$ LANGUAGE plpgsql;

--EXAMPLE--
-- select * from search_course('Freshman',1082); --

/*-----------------------------------------------------------------------------*/

--5-PastCourseStats--
create or replace function past_course_stats(
	CNAME text 			--course id
	)
returns table (
	course_name text,
	a_percent numeric(10,2),
	ab_percent numeric(10,2),
	b_percent numeric(10,2),
	bc_percent numeric(10,2),
	c_percent numeric(10,2),
	d_percent numeric(10,2),
	f_percent numeric(10,2),
	s_percent numeric(10,2),
	u_percent numeric(10,2),
	cr_percent numeric(10,2),
	n_percent numeric(10,2),
	p_percent numeric(10,2),
	i_percent numeric(10,2),
	nw_percent numeric(10,2),
	nr_percent numeric(10,2),
	other_percent numeric(10,2))
	as $$
DECLARE
	CNAME text :='%' || CNAME || '%' ;
begin
	return query
	(SELECT courses.course_name,
		AVG(grade_distribution_percentages.a_count_p)::numeric(10,2) as a_count_p,
		AVG(grade_distribution_percentages.ab_count_p)::numeric(10,2) as ab_count_p,
		AVG(grade_distribution_percentages.b_count_p)::numeric(10,2) as b_count_p,
		AVG(grade_distribution_percentages.bc_count_p)::numeric(10,2) as bc_count_p,
		AVG(grade_distribution_percentages.c_count_p)::numeric(10,2) as c_count_p,
		AVG(grade_distribution_percentages.d_count_p)::numeric(10,2) as d_count_p,
		AVG(grade_distribution_percentages.f_count_p)::numeric(10,2) as f_count_p,
		AVG(grade_distribution_percentages.s_count_p)::numeric(10,2) as s_count_p,
		AVG(grade_distribution_percentages.u_count_p)::numeric(10,2) as u_count_p,
		AVG(grade_distribution_percentages.cr_count_p)::numeric(10,2) as cr_count_p,
		AVG(grade_distribution_percentages.n_count_p)::numeric(10,2) as n_count_p,
		AVG(grade_distribution_percentages.p_count_p)::numeric(10,2) as p_count_p,
		AVG(grade_distribution_percentages.i_count_p)::numeric(10,2) as i_count_p,
		AVG(grade_distribution_percentages.nw_count_p)::numeric(10,2) as nw_count_p,
		AVG(grade_distribution_percentages.nr_count_p)::numeric(10,2) as nr_count_p,
		AVG(grade_distribution_percentages.other_count_p)::numeric(10,2) as other_count_p
		FROM
		(
			select uuid, name as course_name from  courses where courses.name ilike CNAME
		) as courses , course_offerings,grade_distribution_percentages WHERE
		--join condition for courses
		courses.uuid=course_offerings.course_uuid and
		--join condition for grade_distribution_percentages
		grade_distribution_percentages.course_offering_uuid=course_offerings.uuid group by courses.course_name


	);
end $$ LANGUAGE plpgsql;

--EXAMPLE--
-- select * FROM past_course_stats('database'); --

/*-----------------------------------------------------------------------------*/

--adding a course
create or replace function add_course(
	student_id bigint,
	section_number int,
	course_offering_uuid text)
returns void as $$
begin
	insert into course_registrations values (course_offering_uuid,section_number, student_id);
end $$ LANGUAGE plpgsql;

--EXAMPLE--
	-- select * from add_course()
/*-----------------------------------------------------------------------------*/

create or replace function drop_course(
	student_id bigint,
	course_offering_uuid text)
returns void as $$
begin
	delete from course_registrations where course_registrations.course_offering =course_offering_uuid and course_registrations.student_id= student_id;
	insert into rejected_requests values (course_offering_uuid, student_id);

end $$ LANGUAGE plpgsql;
/*-----------------------------------------------------------------------------*/
create or replace function get_daily_schedule(
	SID bigint)
returns table (
	course_name text,
	section_number int,
	facility_code text,
	room_code text,
	start_time int ,
	end_time int ,
	m boolean ,
	t boolean ,
	w boolean ,
	th boolean ,
	f boolean ,
	sa boolean ,
	su boolean )
as $$
begin
return query
	select courses.name as course_name, schedule_room.section_number,
	schedule_room.facility_code, schedule_room.room_code,--room data
	schedule_room.start_time,schedule_room.end_time,mon,tues,wed,thurs,fri,sat,sun --schedule data
	from
	(
		select course_offering, course_registrations.section_number from course_registrations where course_registrations.student_id=SID
	)
	as t, courses, course_offerings, schedule_room
	where t.course_offering=schedule_room.course_offering_uuid and t.section_number=schedule_room.section_number
	and t.course_offering=course_offerings.uuid
	and course_offerings.course_uuid=courses.uuid;
end $$ LANGUAGE plpgsql;

--EXAMPLE
-- select * from get_daily_schedule(1);
/*-----------------------------------------------------------------------------*/
