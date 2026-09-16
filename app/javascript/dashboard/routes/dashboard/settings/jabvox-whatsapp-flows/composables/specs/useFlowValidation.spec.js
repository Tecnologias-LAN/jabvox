import { vi, describe, it, expect, beforeEach } from 'vitest';
import { useFlowValidation } from '../useFlowValidation';
import { wfFlowsAPI } from 'dashboard/api/jabvox/whatsappFlows';

vi.mock('dashboard/api/jabvox/whatsappFlows', () => ({
  wfFlowsAPI: { validate: vi.fn() },
}));

describe('useFlowValidation', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('starts unvalidated with no errors', () => {
    const { errors, validated, isValid } = useFlowValidation();
    expect(errors.value).toEqual([]);
    expect(validated.value).toBe(false);
    expect(isValid.value).toBe(false);
  });

  it('populates errors and marks validated=true after a successful call', async () => {
    wfFlowsAPI.validate.mockResolvedValue({
      data: {
        valid: false,
        errors: [
          {
            screen_id: 'welcome',
            component_id: 'cmp_1',
            field: 'text',
            message: 'Requerido',
          },
        ],
      },
    });
    const { validate, errors, validated, isValid } = useFlowValidation();
    const ok = await validate('flow_1');
    expect(ok).toBe(false);
    expect(errors.value).toHaveLength(1);
    expect(validated.value).toBe(true);
    expect(isValid.value).toBe(false);
  });

  it('isValid is true only when validated and there are no errors', async () => {
    wfFlowsAPI.validate.mockResolvedValue({
      data: { valid: true, errors: [] },
    });
    const { validate, isValid } = useFlowValidation();
    await validate('flow_1');
    expect(isValid.value).toBe(true);
  });

  it('surfaces a generic error entry when the request itself fails', async () => {
    wfFlowsAPI.validate.mockRejectedValue({
      response: { data: { error: 'Servidor caído' } },
    });
    const { validate, errors } = useFlowValidation();
    const ok = await validate('flow_1');
    expect(ok).toBe(false);
    expect(errors.value[0].message).toBe('Servidor caído');
  });

  it('errorsForScreen and errorsForComponent filter correctly', async () => {
    wfFlowsAPI.validate.mockResolvedValue({
      data: {
        valid: false,
        errors: [
          { screen_id: 'welcome', component_id: 'cmp_1', message: 'a' },
          { screen_id: 'rating', component_id: 'cmp_2', message: 'b' },
        ],
      },
    });
    const { validate, errorsForScreen, errorsForComponent } =
      useFlowValidation();
    await validate('flow_1');
    expect(errorsForScreen('welcome')).toHaveLength(1);
    expect(errorsForComponent('rating', 'cmp_2')).toHaveLength(1);
    expect(errorsForComponent('welcome', 'cmp_2')).toHaveLength(0);
  });

  it('reset() clears errors and validated flag', async () => {
    wfFlowsAPI.validate.mockResolvedValue({
      data: { valid: false, errors: [{ message: 'x' }] },
    });
    const { validate, reset, errors, validated } = useFlowValidation();
    await validate('flow_1');
    reset();
    expect(errors.value).toEqual([]);
    expect(validated.value).toBe(false);
  });
});
