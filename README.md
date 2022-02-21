# MSSQL Admin Exercises
Various exercises related to database administration

## Table of contents
* [Motivation](#motivation)
* [Exercise details](#exercise-details)

## Motivation
The main goal of this project was to better understand MSSQL and database administration.  
In addition, I wanted to create some handy procedures such as removing foreign keys, backing up databases, etc.

## Exercise details

### Exercise 1
  The task of this exercise was to create a procedure for
  - saving all foreign keys
  - deleting all foreign keys
  - restoring all foreign keys

### Exercise 2
  The task of this exercise was to create a procedure for
  - backing up single database
  - backing up multiple databases

and schedule backups of all databases to be run via SQL Agent

### Exercise 3
  This exercise goal was to
  - create a trigger on insert to remember an invoice in another database
  - create a trigger on update (only specific column) in another database
  
### Exercise 4
   The task of this exercise was to create a procedure for
   - creating indexes on foreign keys that do not have the indexes
   
### Exercise 5
  The task of this exercise was to create a procedure for
  - removing column with existing constraints
