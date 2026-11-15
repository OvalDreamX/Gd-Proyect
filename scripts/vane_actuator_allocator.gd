extends RefCounted
class_name VaneActuatorAllocator

## Pure, deterministic bounded-wrench allocator.
##
## Each actuator is a bidirectional scalar-force source. Its local axis and
## position define its six-dimensional wrench column; control weights determine
## whether, and how strongly, it may be recruited for the currently requested
## channels. This class does not read scene nodes or apply physics forces.
##
## Actuator input dictionary:
## {
##   "id": StringName,
##   "position_local": Vector3,
##   "axis_local": Vector3,
##   "max_force_n": float,
##   "control_weights": Dictionary,
##   "enabled": bool (optional, default true)
## }
##
## Positive FCC command signs preserve the existing contract:
## pitch -> +X torque, yaw -> -Y torque, roll -> -Z torque.
## Lift is +Y force; main_thrust is -Z force.
##
## Translation channels are ship-local force demands:
## translate_x -> +X, translate_y -> +Y, translate_z -> +Z.
## They are supported by the allocator but are not yet bound to pilot inputs.

const CONTROL_CHANNELS: Array[StringName] = [
	&"pitch", &"roll", &"yaw", &"lift", &"main_thrust",
	&"translate_x", &"translate_y", &"translate_z"
]
const MINIMUM_SQUARED_LENGTH: float = 0.000001
const DEFAULT_ITERATIONS: int = 96
const DEFAULT_REGULARIZATION: float = 0.0001
const CONVERGENCE_OUTPUT_DELTA: float = 0.00005
const WRENCH_COMPONENT_COUNT: int = 6
const LINEAR_SOLVE_EPSILON: float = 0.000000000001


static func allocate(
		actuators: Array[Dictionary],
		demands: Dictionary,
		center_of_mass_local: Vector3,
		reference_force_newtons: float,
		characteristic_length_m: float,
		iterations: int = DEFAULT_ITERATIONS,
		regularization: float = DEFAULT_REGULARIZATION
) -> Dictionary:
	var validation_errors := PackedStringArray()
	if not _is_finite_vector3(center_of_mass_local):
		validation_errors.append("Center of mass must contain finite coordinates.")
	if not is_finite(reference_force_newtons) or reference_force_newtons <= 0.0:
		validation_errors.append("Reference force must be finite and greater than zero.")
	if not is_finite(characteristic_length_m) or characteristic_length_m <= 0.0:
		validation_errors.append("Characteristic length must be finite and greater than zero.")
	if not is_finite(regularization) or regularization <= 0.0:
		validation_errors.append("Regularization must be finite and greater than zero.")

	var normalized_demands: Dictionary = {}
	for channel_variant: Variant in demands.keys():
		var channel: StringName = StringName(str(channel_variant))
		if not CONTROL_CHANNELS.has(channel):
			validation_errors.append("Unknown demand channel '%s'." % str(channel_variant))
			continue
		var demand_variant: Variant = demands[channel_variant]
		if typeof(demand_variant) != TYPE_INT and typeof(demand_variant) != TYPE_FLOAT:
			validation_errors.append("Demand '%s' must be numeric." % String(channel))
			continue
		var demand_value: float = float(demand_variant)
		if not is_finite(demand_value):
			validation_errors.append("Demand '%s' must be finite." % String(channel))
			continue
		normalized_demands[channel] = clampf(demand_value, -1.0, 1.0)

	var actuators_by_id: Dictionary = {}
	for actuator_variant: Dictionary in actuators:
		var actuator_id: StringName = StringName(str(actuator_variant.get("id", "")))
		if actuator_id.is_empty():
			validation_errors.append("Every actuator requires a non-empty id.")
			continue
		if actuators_by_id.has(actuator_id):
			validation_errors.append("Duplicate actuator id '%s'." % String(actuator_id))
			continue

		var position_variant: Variant = actuator_variant.get("position_local", Vector3.ZERO)
		var axis_variant: Variant = actuator_variant.get("axis_local", Vector3.ZERO)
		if typeof(position_variant) != TYPE_VECTOR3 or not _is_finite_vector3(position_variant):
			validation_errors.append("Actuator %s has an invalid local position." % String(actuator_id))
			continue
		if typeof(axis_variant) != TYPE_VECTOR3 or not _is_finite_vector3(axis_variant):
			validation_errors.append("Actuator %s has an invalid local axis." % String(actuator_id))
			continue
		var axis_local: Vector3 = axis_variant
		if axis_local.length_squared() <= MINIMUM_SQUARED_LENGTH:
			validation_errors.append("Actuator %s has a zero local axis." % String(actuator_id))
			continue

		var max_force_variant: Variant = actuator_variant.get("max_force_n", 0.0)
		if (typeof(max_force_variant) != TYPE_INT and typeof(max_force_variant) != TYPE_FLOAT):
			validation_errors.append("Actuator %s has a non-numeric maximum force." % String(actuator_id))
			continue
		var max_force_n: float = float(max_force_variant)
		if not is_finite(max_force_n) or max_force_n < 0.0:
			validation_errors.append("Actuator %s has an invalid maximum force." % String(actuator_id))
			continue

		var weights_variant: Variant = actuator_variant.get("control_weights", {})
		if typeof(weights_variant) != TYPE_DICTIONARY:
			validation_errors.append("Actuator %s control_weights must be a Dictionary." % String(actuator_id))
			continue
		var weights: Dictionary = weights_variant
		var normalized_weights: Dictionary = {}
		var invalid_weights: bool = false
		for weight_channel_variant: Variant in weights.keys():
			var weight_channel: StringName = StringName(str(weight_channel_variant))
			if not CONTROL_CHANNELS.has(weight_channel):
				validation_errors.append(
					"Actuator %s has unknown control channel '%s'."
					% [String(actuator_id), str(weight_channel_variant)]
				)
				invalid_weights = true
				continue
			var weight_variant: Variant = weights[weight_channel_variant]
			if not _is_whole_control_weight(weight_variant):
				validation_errors.append(
					"Actuator %s has invalid %s weight; expected a whole number from 0 to 100."
					% [String(actuator_id), String(weight_channel)]
				)
				invalid_weights = true
				continue
			if normalized_weights.has(weight_channel):
				validation_errors.append(
					"Actuator %s defines control channel '%s' more than once."
					% [String(actuator_id), String(weight_channel)]
				)
				invalid_weights = true
				continue
			normalized_weights[weight_channel] = int(weight_variant)
		if invalid_weights:
			continue

		var enabled_variant: Variant = actuator_variant.get("enabled", true)
		if typeof(enabled_variant) != TYPE_BOOL:
			validation_errors.append("Actuator %s enabled flag must be boolean." % String(actuator_id))
			continue

		actuators_by_id[actuator_id] = {
			"id": actuator_id,
			"position_local": position_variant,
			"axis_local": axis_local.normalized(),
			"max_force_n": max_force_n,
			"control_weights": normalized_weights,
			"enabled": enabled_variant,
		}

	if not validation_errors.is_empty():
		return _failure_result(validation_errors)

	var target_force_local := Vector3(
		float(normalized_demands.get(&"translate_x", 0.0)),
		float(normalized_demands.get(&"lift", 0.0))
			+ float(normalized_demands.get(&"translate_y", 0.0)),
		float(normalized_demands.get(&"translate_z", 0.0))
			- float(normalized_demands.get(&"main_thrust", 0.0))
	)
	target_force_local *= reference_force_newtons

	var target_torque_local := Vector3(
		float(normalized_demands.get(&"pitch", 0.0)),
		-float(normalized_demands.get(&"yaw", 0.0)),
		-float(normalized_demands.get(&"roll", 0.0))
	) * reference_force_newtons * characteristic_length_m

	var target_force_normalized: Vector3 = target_force_local / reference_force_newtons
	var target_torque_normalized: Vector3 = (
		target_torque_local / (reference_force_newtons * characteristic_length_m)
	)

	var total_active_demand: float = 0.0
	for channel: StringName in CONTROL_CHANNELS:
		total_active_demand += absf(float(normalized_demands.get(channel, 0.0)))

	var columns: Array[Dictionary] = []
	var sorted_ids: Array[StringName] = []
	for actuator_id_variant: Variant in actuators_by_id.keys():
		sorted_ids.append(StringName(str(actuator_id_variant)))
	sorted_ids.sort()

	for actuator_id: StringName in sorted_ids:
		var actuator: Dictionary = actuators_by_id[actuator_id]
		if not bool(actuator["enabled"]) or float(actuator["max_force_n"]) <= 0.0:
			continue

		var weights: Dictionary = actuator["control_weights"]
		var weighted_control_sum: float = 0.0
		for channel: StringName in CONTROL_CHANNELS:
			var channel_demand: float = absf(float(normalized_demands.get(channel, 0.0)))
			if channel_demand <= 0.000001:
				continue
			weighted_control_sum += channel_demand * float(weights.get(channel, 0))
		if total_active_demand <= 0.000001:
			continue
		var effective_control_weight: float = weighted_control_sum / total_active_demand
		if effective_control_weight <= 0.000001:
			continue

		var axis_local: Vector3 = actuator["axis_local"]
		var lever_arm_local: Vector3 = actuator["position_local"] - center_of_mass_local
		var max_force_n: float = float(actuator["max_force_n"])
		var force_column: Vector3 = axis_local * (max_force_n / reference_force_newtons)
		var torque_column: Vector3 = (
			lever_arm_local.cross(axis_local)
			* (max_force_n / (reference_force_newtons * characteristic_length_m))
		)
		var weight_ratio: float = 100.0 / effective_control_weight
		var penalty: float = regularization * weight_ratio * weight_ratio
		columns.append({
			"id": actuator_id,
			"position_local": actuator["position_local"],
			"axis_local": axis_local,
			"max_force_n": max_force_n,
			"control_weight": effective_control_weight,
			"force_column": force_column,
			"torque_column": torque_column,
			"penalty": penalty,
			"output": 0.0,
		})

	var residual_force: Vector3 = target_force_normalized
	var residual_torque: Vector3 = target_torque_normalized
	var warm_start_outputs: PackedFloat64Array = _solve_unbounded_weighted_least_squares(
		columns, target_force_normalized, target_torque_normalized
	)
	if not columns.is_empty() and warm_start_outputs.size() != columns.size():
		return _failure_result(PackedStringArray([
			"The six-dimensional actuator allocation solve failed its numerical checks."
		]))
	if warm_start_outputs.size() == columns.size():
		# The dual six-dimensional solve gives the exact regularized unconstrained
		# minimizer. Projecting it into each actuator's bounds provides a strong,
		# ordering-independent starting point for the bounded refinement below.
		for column_index: int in range(columns.size()):
			var column: Dictionary = columns[column_index]
			var output: float = clampf(warm_start_outputs[column_index], -1.0, 1.0)
			column["output"] = output
			columns[column_index] = column
			var force_column: Vector3 = column["force_column"]
			var torque_column: Vector3 = column["torque_column"]
			residual_force -= force_column * output
			residual_torque -= torque_column * output

	var safe_iterations: int = clampi(iterations, 1, 512)
	var performed_iterations: int = 0
	var converged: bool = columns.is_empty()

	# Cyclic coordinate descent refines only actuator-bound violations and the
	# small residual introduced by projection. The dual warm start avoids the
	# severe order bias and slow convergence of zero-start coordinate descent
	# when multiple actuators have nearly identical geometry.
	# The bounded objective remains:
	# ||achieved_wrench - requested_wrench||^2 + sum(penalty_i * output_i^2).
	for _iteration: int in range(safe_iterations):
		performed_iterations += 1
		var maximum_output_change: float = 0.0
		for column_index: int in range(columns.size()):
			var column: Dictionary = columns[column_index]
			var force_column: Vector3 = column["force_column"]
			var torque_column: Vector3 = column["torque_column"]
			var old_output: float = float(column["output"])
			var penalty: float = float(column["penalty"])
			var denominator: float = (
				force_column.length_squared()
				+ torque_column.length_squared()
				+ penalty
			)
			if denominator <= 0.0000001:
				continue
			var gradient: float = (
				force_column.dot(residual_force)
				+ torque_column.dot(residual_torque)
				- penalty * old_output
			)
			var new_output: float = clampf(old_output + gradient / denominator, -1.0, 1.0)
			var output_delta: float = new_output - old_output
			if absf(output_delta) <= 0.000000001:
				continue
			residual_force -= force_column * output_delta
			residual_torque -= torque_column * output_delta
			column["output"] = new_output
			columns[column_index] = column
			maximum_output_change = maxf(maximum_output_change, absf(output_delta))
		if maximum_output_change <= CONVERGENCE_OUTPUT_DELTA:
			converged = true
			break

	var achieved_force_local := Vector3.ZERO
	var achieved_torque_local := Vector3.ZERO
	var actuator_outputs: Array[Dictionary] = []
	var saturated_count: int = 0

	for column_value: Dictionary in columns:
		var output: float = float(column_value["output"])
		var force_n: Vector3 = (
			column_value["axis_local"] * float(column_value["max_force_n"]) * output
		)
		var torque_nm: Vector3 = (
			(column_value["position_local"] - center_of_mass_local).cross(force_n)
		)
		achieved_force_local += force_n
		achieved_torque_local += torque_nm
		var saturated: bool = absf(output) >= 0.999
		if saturated:
			saturated_count += 1
		actuator_outputs.append({
			"id": column_value["id"],
			"output": output,
			"control_weight": column_value["control_weight"],
			"max_force_n": column_value["max_force_n"],
			"force_local_n": force_n,
			"torque_local_nm": torque_nm,
			"saturated": saturated,
		})

	var force_error: Vector3 = target_force_local - achieved_force_local
	var torque_error: Vector3 = target_torque_local - achieved_torque_local
	var normalized_error_squared: float = (
		(force_error / reference_force_newtons).length_squared()
		+ (torque_error / (reference_force_newtons * characteristic_length_m)).length_squared()
	)

	return {
		"success": true,
		"errors": PackedStringArray(),
		"target_force_local_n": target_force_local,
		"target_torque_local_nm": target_torque_local,
		"achieved_force_local_n": achieved_force_local,
		"achieved_torque_local_nm": achieved_torque_local,
		"force_residual_local_n": force_error,
		"torque_residual_local_nm": torque_error,
		"normalized_error": sqrt(normalized_error_squared),
		"actuator_outputs": actuator_outputs,
		"eligible_actuator_count": columns.size(),
		"saturated_actuator_count": saturated_count,
		"iterations": performed_iterations,
		"converged": converged,
	}


## Solves the regularized least-squares problem in wrench space rather than
## actuator space. The system has a fixed six-dimensional matrix regardless of
## how many actuators a ship defines:
##   min ||A*x - b||^2 + sum(p_i*x_i^2)
##   x = P^-1 * A^T * (I + A*P^-1*A^T)^-1 * b
## The returned values are unconstrained; the caller clamps them and lets the
## bounded coordinate refinement recover any residual from saturated actuators.
static func _solve_unbounded_weighted_least_squares(
		columns: Array[Dictionary],
		target_force: Vector3,
		target_torque: Vector3
) -> PackedFloat64Array:
	var empty_result := PackedFloat64Array()
	if columns.is_empty():
		return empty_result

	var matrix: Array[PackedFloat64Array] = []
	for row_index: int in range(WRENCH_COMPONENT_COUNT):
		var row := PackedFloat64Array()
		row.resize(WRENCH_COMPONENT_COUNT)
		for column_index: int in range(WRENCH_COMPONENT_COUNT):
			row[column_index] = 1.0 if row_index == column_index else 0.0
		matrix.append(row)

	var wrench_columns: Array[PackedFloat64Array] = []
	var rhs := PackedFloat64Array([
		target_force.x,
		target_force.y,
		target_force.z,
		target_torque.x,
		target_torque.y,
		target_torque.z,
	])

	for column: Dictionary in columns:
		var force_column: Vector3 = column["force_column"]
		var torque_column: Vector3 = column["torque_column"]
		var wrench := PackedFloat64Array([
			force_column.x,
			force_column.y,
			force_column.z,
			torque_column.x,
			torque_column.y,
			torque_column.z,
		])
		var penalty: float = float(column["penalty"])
		if not is_finite(penalty) or penalty <= 0.0:
			return empty_result
		wrench_columns.append(wrench)
		var inverse_penalty: float = 1.0 / penalty
		for row_index: int in range(WRENCH_COMPONENT_COUNT):
			var row: PackedFloat64Array = matrix[row_index]
			for column_index: int in range(WRENCH_COMPONENT_COUNT):
				row[column_index] += wrench[row_index] * wrench[column_index] * inverse_penalty
			matrix[row_index] = row

	var dual_solution: PackedFloat64Array = _solve_linear_system_6x6(matrix, rhs)
	if dual_solution.size() != WRENCH_COMPONENT_COUNT:
		return empty_result

	var outputs := PackedFloat64Array()
	outputs.resize(columns.size())
	for index: int in range(columns.size()):
		var column: Dictionary = columns[index]
		var wrench: PackedFloat64Array = wrench_columns[index]
		var projection: float = 0.0
		for component: int in range(WRENCH_COMPONENT_COUNT):
			projection += wrench[component] * dual_solution[component]
		var output: float = projection / float(column["penalty"])
		if not is_finite(output):
			return empty_result
		outputs[index] = output
	return outputs


## Partial-pivot Gauss-Jordan elimination. The matrix is positive definite due
## to its identity term, but pivoting still protects against scale differences
## between the force and torque contributions.
static func _solve_linear_system_6x6(
		matrix: Array[PackedFloat64Array],
		rhs: PackedFloat64Array
) -> PackedFloat64Array:
	var empty_result := PackedFloat64Array()
	if matrix.size() != WRENCH_COMPONENT_COUNT or rhs.size() != WRENCH_COMPONENT_COUNT:
		return empty_result

	var augmented: Array[PackedFloat64Array] = []
	for row_index: int in range(WRENCH_COMPONENT_COUNT):
		if matrix[row_index].size() != WRENCH_COMPONENT_COUNT:
			return empty_result
		var row := PackedFloat64Array()
		row.resize(WRENCH_COMPONENT_COUNT + 1)
		for column_index: int in range(WRENCH_COMPONENT_COUNT):
			row[column_index] = matrix[row_index][column_index]
		row[WRENCH_COMPONENT_COUNT] = rhs[row_index]
		augmented.append(row)

	for pivot_index: int in range(WRENCH_COMPONENT_COUNT):
		var best_row: int = pivot_index
		var best_magnitude: float = absf(augmented[pivot_index][pivot_index])
		for candidate_row: int in range(pivot_index + 1, WRENCH_COMPONENT_COUNT):
			var candidate_magnitude: float = absf(augmented[candidate_row][pivot_index])
			if candidate_magnitude > best_magnitude:
				best_magnitude = candidate_magnitude
				best_row = candidate_row
		if not is_finite(best_magnitude) or best_magnitude <= LINEAR_SOLVE_EPSILON:
			return empty_result
		if best_row != pivot_index:
			var swap_row: PackedFloat64Array = augmented[pivot_index]
			augmented[pivot_index] = augmented[best_row]
			augmented[best_row] = swap_row

		var pivot_value: float = augmented[pivot_index][pivot_index]
		var pivot_row: PackedFloat64Array = augmented[pivot_index]
		for column_index: int in range(pivot_index, WRENCH_COMPONENT_COUNT + 1):
			pivot_row[column_index] /= pivot_value
		augmented[pivot_index] = pivot_row

		for row_index: int in range(WRENCH_COMPONENT_COUNT):
			if row_index == pivot_index:
				continue
			var elimination_row: PackedFloat64Array = augmented[row_index]
			var factor: float = elimination_row[pivot_index]
			if absf(factor) <= LINEAR_SOLVE_EPSILON:
				continue
			for column_index: int in range(pivot_index, WRENCH_COMPONENT_COUNT + 1):
				elimination_row[column_index] -= factor * pivot_row[column_index]
			augmented[row_index] = elimination_row

	var solution := PackedFloat64Array()
	solution.resize(WRENCH_COMPONENT_COUNT)
	for row_index: int in range(WRENCH_COMPONENT_COUNT):
		var value: float = augmented[row_index][WRENCH_COMPONENT_COUNT]
		if not is_finite(value):
			return empty_result
		solution[row_index] = value
	return solution


static func _is_whole_control_weight(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var numeric_value: float = float(value)
	return (
		is_finite(numeric_value)
		and numeric_value >= 0.0
		and numeric_value <= 100.0
		and is_equal_approx(numeric_value, roundf(numeric_value))
	)


static func _is_finite_vector3(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


static func _failure_result(errors: PackedStringArray) -> Dictionary:
	return {
		"success": false,
		"errors": errors,
		"target_force_local_n": Vector3.ZERO,
		"target_torque_local_nm": Vector3.ZERO,
		"achieved_force_local_n": Vector3.ZERO,
		"achieved_torque_local_nm": Vector3.ZERO,
		"force_residual_local_n": Vector3.ZERO,
		"torque_residual_local_nm": Vector3.ZERO,
		"normalized_error": 0.0,
		"actuator_outputs": [],
		"eligible_actuator_count": 0,
		"saturated_actuator_count": 0,
		"iterations": 0,
		"converged": false,
	}
